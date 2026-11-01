#include <furi.h>
#include <furi_hal.h>
#include <gui/gui.h>
#include <gui/elements.h>
#include <input/input.h>
#include <notification/notification_messages.h>
#include <storage/storage.h>
#include <bt/bt_service/bt.h>

#include "paste_profile.h"
#include "clipboard_screen.h"

#define TAG "BleClipboard"

#define KEYS_PATH       APP_DATA_PATH(".ble_clipboard_usb.keys")
#define LAYOUT_PATH     EXT_PATH("badusb/assets/layouts/tr-TR.kl")
#define PROTOCOL_VER    2
#define RX_CAPACITY     4096
#define TYPE_CAPACITY   3072
#define ACTION_DELAY_MS 900

typedef enum {
    CommandHello = 0x01,
    CommandType = 0x02,
    CommandPaste = 0x03,
    CommandCancel = 0x04,
    ResponseReady = 0x81,
    ResponseAccepted = 0x82,
    ResponseDone = 0x83,
    ResponseError = 0xFF,
} ProtocolCommand;

typedef enum {
    PendingNone,
    PendingType,
} PendingAction;

typedef struct {
    Gui* gui;
    Bt* bt;
    Storage* storage;
    NotificationApp* notifications;
    ViewPort* view_port;
    FuriMessageQueue* input_queue;
    FuriMutex* mutex;
    FuriHalBleProfileBase* profile;
    FuriHalUsbInterface* previous_usb;
    bool usb_started;

    volatile bool connected;
    bool last_connected;
    bool authenticated;
    char status[96];

    uint8_t rx[RX_CAPACITY];
    uint16_t rx_size;
    uint16_t rx_expected;
    bool rx_ready;
    bool rx_invalid;

    uint8_t type_buffer[TYPE_CAPACITY];
    uint16_t type_size;
    uint16_t type_position;
    uint16_t layout[128];
    bool turkish_layout_available;
    bool use_turkish_layout;
    PendingAction pending_action;
    uint32_t action_at;
} ClipboardApp;

static void status_set(ClipboardApp* app, const char* status) {
    furi_check(furi_mutex_acquire(app->mutex, FuriWaitForever) == FuriStatusOk);
    snprintf(app->status, sizeof(app->status), "%s", status);
    furi_check(furi_mutex_release(app->mutex) == FuriStatusOk);
    view_port_update(app->view_port);
}

static void draw_callback(Canvas* canvas, void* context) {
    ClipboardApp* app = context;
    char status[sizeof(app->status)];
    furi_check(furi_mutex_acquire(app->mutex, FuriWaitForever) == FuriStatusOk);
    snprintf(status, sizeof(status), "%s", app->status);
    furi_check(furi_mutex_release(app->mutex) == FuriStatusOk);

    clipboard_screen_draw(canvas, status);
}

static void input_callback(InputEvent* event, void* context) {
    ClipboardApp* app = context;
    furi_message_queue_put(app->input_queue, event, 0);
}

static void bt_status_callback(BtStatus status, void* context) {
    ClipboardApp* app = context;
    app->connected = status == BtStatusConnected;
}

static uint16_t serial_callback(SerialServiceEvent event, void* context) {
    ClipboardApp* app = context;
    if(event.event != SerialServiceEventTypeDataReceived) return RX_CAPACITY - app->rx_size;

    furi_check(furi_mutex_acquire(app->mutex, FuriWaitForever) == FuriStatusOk);
    if(!app->rx_ready && event.data.size <= RX_CAPACITY - app->rx_size) {
        memcpy(app->rx + app->rx_size, event.data.buffer, event.data.size);
        app->rx_size += event.data.size;
        if(app->rx_size >= 4 && app->rx_expected == 0) {
            uint32_t expected = 4U + app->rx[2] + ((uint32_t)app->rx[3] << 8);
            if(expected > RX_CAPACITY || app->rx[0] != PROTOCOL_VER) {
                app->rx_size = 0;
                app->rx_expected = 0;
                app->rx_invalid = true;
            } else {
                app->rx_expected = expected;
            }
        }
        if(app->rx_expected && app->rx_size >= app->rx_expected) {
            app->rx_ready = true;
        }
    }
    uint16_t available = RX_CAPACITY - app->rx_size;
    furi_check(furi_mutex_release(app->mutex) == FuriStatusOk);
    return available;
}

static void send_response(ClipboardApp* app, ProtocolCommand command, const char* text) {
    uint8_t buffer[128];
    uint16_t size = text ? strlen(text) : 0;
    size = MIN(size, sizeof(buffer) - 4);
    buffer[0] = PROTOCOL_VER;
    buffer[1] = command;
    buffer[2] = size & 0xFF;
    buffer[3] = size >> 8;
    if(size) memcpy(buffer + 4, text, size);
    if(!ble_profile_paste_tx(app->profile, buffer, size + 4)) {
        app->pending_action = PendingNone;
        status_set(app, "Connection error\nReconnect from Mac");
    }
}

static void schedule_action(ClipboardApp* app, PendingAction action) {
    app->pending_action = action;
    app->action_at = furi_get_tick() + furi_ms_to_ticks(ACTION_DELAY_MS);
    send_response(app, ResponseAccepted, "type");
    status_set(app, "Sending text\nUSB keyboard");
}

static void process_packet(ClipboardApp* app) {
    uint8_t packet[RX_CAPACITY];
    uint16_t size;

    furi_check(furi_mutex_acquire(app->mutex, FuriWaitForever) == FuriStatusOk);
    if(app->rx_invalid) {
        app->rx_invalid = false;
        furi_mutex_release(app->mutex);
        send_response(app, ResponseError, "invalid frame");
        return;
    }
    if(!app->rx_ready) {
        furi_mutex_release(app->mutex);
        return;
    }
    size = app->rx_expected;
    memcpy(packet, app->rx, size);
    app->rx_size = 0;
    app->rx_expected = 0;
    app->rx_ready = false;
    furi_check(furi_mutex_release(app->mutex) == FuriStatusOk);

    uint16_t payload_size = size - 4;
    uint8_t* payload = packet + 4;
    if(packet[0] != PROTOCOL_VER) {
        send_response(app, ResponseError, "protocol version");
        return;
    }

    switch(packet[1]) {
    case CommandHello:
        if(payload_size == strlen("BTPASTE-MAC/2") &&
           memcmp(payload, "BTPASTE-MAC/2", payload_size) == 0) {
            app->authenticated = true;
            send_response(app, ResponseReady, furi_hal_version_get_name_ptr());
            status_set(app, "Mac connected\nReady for USB text");
            notification_message(app->notifications, &sequence_success);
        } else {
            send_response(app, ResponseError, "handshake rejected");
        }
        break;
    case CommandType:
        if(!app->authenticated) {
            send_response(app, ResponseError, "not authenticated");
        } else if(app->pending_action != PendingNone) {
            send_response(app, ResponseError, "busy");
        } else if(!app->usb_started || !furi_hal_hid_is_connected()) {
            send_response(app, ResponseError, "USB target not connected");
        } else if(payload_size < 2 || payload_size > TYPE_CAPACITY) {
            send_response(app, ResponseError, "text size");
        } else if(payload[0] > 1 || (payload[0] == 1 && !app->turkish_layout_available)) {
            send_response(app, ResponseError, "keyboard layout unavailable");
        } else {
            bool ascii = true;
            for(uint16_t i = 1; i < payload_size; i++) {
                if((payload[i] < 32 || payload[i] > 126) && payload[i] != '\n' &&
                   payload[i] != '\r' && payload[i] != '\t') {
                    ascii = false;
                    break;
                }
            }
            if(!ascii) {
                send_response(app, ResponseError, "type supports ASCII");
            } else {
                app->use_turkish_layout = payload[0] == 1;
                memcpy(app->type_buffer, payload + 1, payload_size - 1);
                app->type_size = payload_size - 1;
                app->type_position = 0;
                schedule_action(app, PendingType);
            }
        }
        break;
    case CommandPaste:
        send_response(app, ResponseError, "USB target requires text, not Command-V");
        break;
    case CommandCancel:
        app->pending_action = PendingNone;
        app->type_size = 0;
        furi_hal_hid_kb_release_all();
        send_response(app, ResponseDone, "cancelled");
        status_set(app, "Cancelled\nReady");
        break;
    default:
        send_response(app, ResponseError, "unknown command");
        break;
    }
}

static void type_next(ClipboardApp* app) {
    if(app->type_position >= app->type_size) {
        app->pending_action = PendingNone;
        send_response(app, ResponseDone, "USB keystrokes sent");
        memset(app->type_buffer, 0, sizeof(app->type_buffer));
        status_set(app, "Text sent\nReady");
        notification_message(app->notifications, &sequence_success);
        return;
    }

    uint8_t character = app->type_buffer[app->type_position++];
    uint16_t keycode;
    if(character == '\n' || character == '\r') {
        keycode = HID_KEYBOARD_RETURN;
        if(character == '\r' && app->type_position < app->type_size &&
           app->type_buffer[app->type_position] == '\n') {
            app->type_position++;
        }
    } else if(character == '\t') {
        keycode = HID_KEYBOARD_TAB;
    } else {
        keycode = app->use_turkish_layout ? app->layout[character] : HID_ASCII_TO_KEY(character);
    }

    if(keycode != HID_KEYBOARD_NONE) {
        bool sent = furi_hal_hid_kb_press(keycode);
        furi_delay_ms(10);
        sent = furi_hal_hid_kb_release(keycode) && sent;
        if(!sent) {
            app->pending_action = PendingNone;
            furi_hal_hid_kb_release_all();
            send_response(app, ResponseError, "USB write failed; text may be incomplete");
            status_set(app, "USB write failed\nText may be incomplete");
        }
    }
}

static void process_action(ClipboardApp* app) {
    if(app->pending_action == PendingNone ||
       (int32_t)(furi_get_tick() - app->action_at) < 0) {
        return;
    }

    if(!app->connected || !furi_hal_hid_is_connected()) {
        app->pending_action = PendingNone;
        furi_hal_hid_kb_release_all();
        if(app->connected) send_response(app, ResponseError, "USB target disconnected");
        status_set(app, "Connection lost\nTyping stopped");
    } else {
        type_next(app);
    }
}

static void layout_load(ClipboardApp* app) {
    memset(app->layout, HID_KEYBOARD_NONE, sizeof(app->layout));
    File* file = storage_file_alloc(app->storage);
    if(storage_file_open(file, LAYOUT_PATH, FSAM_READ, FSOM_OPEN_EXISTING)) {
        app->turkish_layout_available =
            storage_file_read(file, app->layout, sizeof(app->layout)) == sizeof(app->layout);
    }
    storage_file_close(file);
    storage_file_free(file);
}

static bool profile_start(ClipboardApp* app) {
    bt_disconnect(app->bt);
    furi_delay_ms(200);
    bt_keys_storage_set_storage_path(app->bt, KEYS_PATH);
    app->profile = bt_profile_start(app->bt, ble_profile_paste, NULL);
    if(!app->profile) return false;
    ble_profile_paste_set_serial_callback(
        app->profile, RX_CAPACITY, serial_callback, app);
    bt_set_status_changed_callback(app->bt, bt_status_callback, app);
    furi_hal_bt_start_advertising();
    return true;
}

static void profile_stop(ClipboardApp* app) {
    if(!app->profile) return;
    bt_set_status_changed_callback(app->bt, NULL, NULL);
    ble_profile_paste_set_serial_callback(app->profile, 0, NULL, NULL);
    bt_disconnect(app->bt);
    furi_delay_ms(200);
    bt_keys_storage_set_default_path(app->bt);
    furi_check(bt_profile_restore_default(app->bt));
    app->profile = NULL;
}

static ClipboardApp* app_alloc(void) {
    ClipboardApp* app = malloc(sizeof(ClipboardApp));
    memset(app, 0, sizeof(ClipboardApp));
    app->gui = furi_record_open(RECORD_GUI);
    app->bt = furi_record_open(RECORD_BT);
    app->storage = furi_record_open(RECORD_STORAGE);
    app->notifications = furi_record_open(RECORD_NOTIFICATION);
    app->input_queue = furi_message_queue_alloc(8, sizeof(InputEvent));
    app->mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    app->view_port = view_port_alloc();
    view_port_draw_callback_set(app->view_port, draw_callback, app);
    view_port_input_callback_set(app->view_port, input_callback, app);
    gui_add_view_port(app->gui, app->view_port, GuiLayerFullscreen);
    status_set(app, "Starting...\nBluetooth to USB");
    layout_load(app);
    if(profile_start(app)) {
        app->previous_usb = furi_hal_usb_get_config();
        app->usb_started = furi_hal_usb_set_config(&usb_hid, NULL);
        status_set(app, app->usb_started ? "Waiting for Mac\nBluetooth: Paste" :
                                         "USB busy\nExit and reopen");
    } else {
        status_set(app, "Bluetooth error\nBack to exit");
    }
    return app;
}

static void app_free(ClipboardApp* app) {
    if(app->usb_started) {
        furi_hal_hid_kb_release_all();
        furi_check(furi_hal_usb_set_config(app->previous_usb, NULL));
    }
    profile_stop(app);
    gui_remove_view_port(app->gui, app->view_port);
    view_port_free(app->view_port);
    furi_mutex_free(app->mutex);
    furi_message_queue_free(app->input_queue);
    furi_record_close(RECORD_NOTIFICATION);
    furi_record_close(RECORD_STORAGE);
    furi_record_close(RECORD_BT);
    furi_record_close(RECORD_GUI);
    memset(app->type_buffer, 0, sizeof(app->type_buffer));
    free(app);
}

int32_t ble_clipboard_app(void* context) {
    UNUSED(context);
    ClipboardApp* app = app_alloc();
    bool running = true;

    while(running) {
        InputEvent event;
        if(furi_message_queue_get(app->input_queue, &event, 8) == FuriStatusOk &&
           event.type == InputTypeShort &&
           (event.key == InputKeyBack || event.key == InputKeyLeft)) {
            running = false;
        }

        if(app->connected != app->last_connected) {
            app->last_connected = app->connected;
            if(!app->connected) {
                app->authenticated = false;
                app->pending_action = PendingNone;
                furi_hal_hid_kb_release_all();
                furi_mutex_acquire(app->mutex, FuriWaitForever);
                app->rx_size = app->rx_expected = 0;
                app->rx_ready = app->rx_invalid = false;
                furi_mutex_release(app->mutex);
                memset(app->type_buffer, 0, sizeof(app->type_buffer));
                status_set(app, "Waiting for Mac\nBluetooth: Paste");
            } else {
                status_set(app, "Pairing...\nWaiting for handshake");
            }
        }
        if(app->profile && app->connected) {
            process_packet(app);
            process_action(app);
        }
    }

    app_free(app);
    return 0;
}
