#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../BluetoothClipboard/transfer_protocol.h"
#include "../../BluetoothClipboard/keyboard_layout.h"
#include "../../BluetoothClipboard/keyboard_text.h"
#include "../../BluetoothClipboard/keyboard_turkish_mac.h"
#include "../../BluetoothClipboard/companion_version.h"

typedef struct {
    ClipboardServer server;
    uint8_t storage[CLIPBOARD_PROGRAM_MAX];
    size_t size, written;
    bool opened, ever_sd, held, usb, fail_open, fail_write, fail_read, fail_layout, fail_press, fail_send;
    unsigned closes, releases, count, mouse_count;
    int mouse_balance;
    bool fail_mouse, fail_save, saved;
    bool fail_random;
    bool fail_keyboard_save;
    unsigned keyboard_saves;
    ClipboardKeyboardSettings persisted_keyboard;
    uint32_t random_state;
    int8_t mouse_dx[4096], mouse_dy[4096];
    uint32_t mouse_at[4096];
    uint32_t progress_cursor;
    bool forced_random;
    uint32_t forced_value;
    ClipboardSaved saved_metadata;
    uint8_t saved_storage[CLIPBOARD_PROGRAM_MAX];
    uint16_t keys[70000];
    uint8_t response[128];
    size_t response_size;
    unsigned messages[256];
    uint32_t now;
} Fixture;
static Fixture f;

static void us_layout(uint16_t layout[128]) {
    memset(layout, 0, 256);
    for(unsigned i = 0; i < 26; i++) { layout['a' + i] = 4 + i; layout['A' + i] = 0x204 + i; }
    const char* digits = "1234567890";
    const char* shifted = "!@#$%^&*()";
    for(unsigned i = 0; i < 10; i++) { layout[(unsigned)digits[i]] = 0x1E + i; layout[(unsigned)shifted[i]] = 0x21E + i; }
    const char* plain = " -=[]\\;'`,./";
    const char* upper = " _+{}|:\"~<>?";
    const uint16_t keys[] = {0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38};
    for(unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        layout[(unsigned)plain[i]] = keys[i];
        layout[(unsigned)upper[i]] = keys[i] | (i ? 0x200 : 0);
    }
}

static bool send_frame(void* context, const uint8_t* data, size_t size) {
    Fixture* x = context;
    if(x->fail_send) return false;
    assert(size <= sizeof(x->response) && size >= 4 && data[0] == 4);
    if(data[1] == ClipboardStarted) x->progress_cursor = 0;
    if(data[1] == ClipboardProgress) {
        uint32_t cursor = clipboard_read_u32(data + 8);
        assert(cursor >= x->progress_cursor && cursor <= clipboard_read_u32(data + 12));
        x->progress_cursor = cursor;
    }
    memcpy(x->response, data, size); x->response_size = size; x->messages[data[1]]++;
    return true;
}
static bool open_store(void* context, size_t size) {
    Fixture* x = context;
    if(x->fail_open) return false;
    assert(size <= sizeof(x->storage));
    x->opened = true; x->size = size; x->written = 0; x->ever_sd |= size > 4096;
    return true;
}
static bool write_store(void* context, size_t offset, const uint8_t* data, size_t size) {
    Fixture* x = context;
    if(x->fail_write) return false;
    assert(x->opened && offset == x->written && size <= x->size - offset);
    memcpy(x->storage + offset, data, size); x->written += size;
    return true;
}
static bool read_store(void* context, size_t offset, uint8_t* output, size_t size) {
    Fixture* x = context;
    if(x->fail_read) return false;
    if(!x->opened || offset > x->written || size > x->written - offset) return false;
    memcpy(output, x->storage + offset, size);
    return true;
}
static void close_store(void* context) {
    Fixture* x = context;
    x->opened = false; x->size = x->written = 0; x->closes++;
    memset(x->storage, 0, sizeof(x->storage));
}
static bool load_layout(void* context, uint8_t id, uint8_t target, uint16_t output[128]) {
    Fixture* x = context;
    if(x->fail_layout || id >= 28 || target > 2) return false;
    if(id == 1 && target == 0) memcpy(output, clipboard_turkish_mac, 256);
    else us_layout(output);
    return true;
}
static bool usb_connected(void* context) { return ((Fixture*)context)->usb; }
static bool press_key(void* context, uint16_t key) {
    Fixture* x = context;
    if(x->fail_press || !x->usb) return false;
    assert(!x->held && x->count < sizeof(x->keys) / sizeof(x->keys[0]));
    x->keys[x->count++] = key; x->held = true;
    return true;
}
static bool release_key(void* context) { Fixture* x = context; x->held = false; x->releases++; return true; }
static bool mouse_move(void* context, int8_t dx, int8_t dy) {
    Fixture* x = context;
    if(x->fail_mouse || !x->usb) return false;
    assert(dx >= -127 && dy >= -127 && (dx || dy));
    if(x->mouse_count < 4096) {
        x->mouse_dx[x->mouse_count] = dx; x->mouse_dy[x->mouse_count] = dy; x->mouse_at[x->mouse_count] = x->now;
    }
    x->mouse_count++; x->mouse_balance += dx;
    return true;
}
static bool save_program(void* context, const ClipboardSaved* saved) {
    Fixture* x = context;
    if(x->fail_save) return false;
    x->saved_metadata = *saved; x->saved = true;
    memcpy(x->saved_storage, x->storage, saved->size);
    return true;
}
static bool random_value(void* context, uint32_t* value) {
    Fixture* x = context;
    if(x->fail_random) return false;
    if(x->forced_random) { *value = x->forced_value; return true; }
    x->random_state = x->random_state * 1664525U + 1013904223U;
    *value = x->random_state;
    return true;
}
static bool save_keyboard(void* context, const ClipboardKeyboardSettings* settings) {
    Fixture* x = context;
    x->keyboard_saves++;
    if(x->fail_keyboard_save) return false;
    x->persisted_keyboard = *settings;
    return true;
}
static void reset(void) {
    memset(&f, 0, sizeof(f)); f.usb = true;
    ClipboardServerIO io = {&f, send_frame, open_store, write_store, read_store, close_store,
                            load_layout, usb_connected, press_key, release_key, mouse_move, save_program, random_value, save_keyboard};
    clipboard_server_init(&f.server, io, "Host Test");
}
static void send_command(uint8_t command, const uint8_t* payload, size_t size) {
    uint8_t frame[CLIPBOARD_FRAME_MAX];
    assert(size <= sizeof(frame) - 4);
    frame[0] = 4; frame[1] = command; clipboard_write_u16(frame + 2, (uint16_t)size);
    if(size) memcpy(frame + 4, payload, size);
    // Exercise headers, UTF-8 and records split across arbitrary GATT writes.
    for(size_t offset = 0; offset < size + 4;) {
        size_t chunk = 1 + (offset % 17);
        if(chunk > size + 4 - offset) chunk = size + 4 - offset;
        clipboard_server_feed(&f.server, frame + offset, chunk, f.now);
        offset += chunk;
    }
}
static void hello(void) {
    send_command(ClipboardHello, (const uint8_t*)"BLECLIP/4", 9);
    assert(f.server.authenticated && f.response[1] == ClipboardReady);
    assert(clipboard_read_u32(f.response + 4) == 65536 && clipboard_read_u16(f.response + 8) == 512);
    assert(f.response[10] == 28 && f.response[11] == 7);
    assert(f.response[12] == 255);
}
static void id_command(uint8_t command, uint32_t id) {
    uint8_t bytes[4]; clipboard_write_u32(bytes, id); send_command(command, bytes, sizeof(bytes));
}
static void begin_mode(const uint8_t* program, size_t size, uint8_t layout, uint8_t target, uint8_t flags) {
    uint8_t bytes[15] = {0}; clipboard_write_u32(bytes, 7); bytes[4] = layout; bytes[5] = target;
    clipboard_write_u32(bytes + 6, (uint32_t)size);
    clipboard_write_u32(bytes + 10, clipboard_crc_update(0xFFFFFFFFU, program, size) ^ 0xFFFFFFFFU);
    bytes[14] = flags;
    send_command(ClipboardBegin, bytes, sizeof(bytes));
}
static void begin(const uint8_t* program, size_t size, uint8_t layout, uint8_t target) {
    begin_mode(program, size, layout, target, 0);
}
static void upload_mode(const uint8_t* program, size_t size, uint8_t layout, uint8_t target, uint8_t flags) {
    begin_mode(program, size, layout, target, flags);
    assert(f.server.state == ClipboardJobReceiving && f.response[1] == ClipboardBegun && f.count == 0);
    for(size_t offset = 0; offset < size;) {
        size_t count = size - offset; if(count > 512) count = 512;
        uint8_t chunk[520]; clipboard_write_u32(chunk, 7); clipboard_write_u32(chunk + 4, (uint32_t)offset);
        memcpy(chunk + 8, program + offset, count);
        send_command(ClipboardChunk, chunk, count + 8);
        offset += count; f.now++;
        assert(f.response[1] == ClipboardChunked && clipboard_read_u32(f.response + 8) == offset);
        assert(f.count == 0);
    }
    id_command(ClipboardCommit, 7);
}
static void upload(const uint8_t* program, size_t size, uint8_t layout, uint8_t target) {
    upload_mode(program, size, layout, target, 0);
}
static size_t text_program(uint8_t* output, const uint8_t* text, size_t size) {
    memcpy(output, "BCM4", 4); clipboard_write_u16(output + 4, 1);
    output[6] = 1; clipboard_write_u32(output + 7, (uint32_t)size); memcpy(output + 11, text, size);
    return size + 11;
}
static void advance(uint32_t duration) {
    for(uint32_t i = 0; i < duration; i += 4) { f.now += 4; clipboard_server_tick(&f.server, f.now, true); }
}
static void finish(void) {
    for(unsigned tick = 0; tick < 1000000 && f.server.state != ClipboardJobIdle; tick++) advance(4);
    assert(f.server.state == ClipboardJobIdle && !f.held && !f.opened);
}

static void protocol_checks(void) {
    uint8_t program[64]; size_t size = text_program(program, (const uint8_t*)"Hi [ENTER]", 10);
    reset(); begin(program, size, 0, 0); assert(!f.opened && f.count == 0 && f.response[1] == ClipboardError);
    hello(); begin(program, size, 0, 0);
    id_command(ClipboardExecute, 7); assert(f.count == 0 && !f.opened && f.response[1] == ClipboardError);

    reset(); hello(); upload(program, size, 0, 0);
    assert(f.response[1] == ClipboardVerified && f.count == 0);
    advance(1000); assert(f.count == 0);
    id_command(ClipboardExecute, 7);
    advance(896); assert(f.count == 0);
    finish(); assert(f.count == 10 && f.response[1] == ClipboardDone && f.response[8] == 0);
    for(unsigned i = 0; i < f.count; i++) assert((f.keys[i] & 0x9900) == 0);
    unsigned count = f.count; id_command(ClipboardExecute, 7); advance(1000); assert(f.count == count);

    reset(); hello(); begin(program, size, 0, 0); id_command(ClipboardCancel, 7);
    assert(f.server.authenticated && !f.opened && !f.count && f.response[8] == 1);
    upload(program, size, 0, 0); assert(f.response[1] == ClipboardVerified);
    id_command(ClipboardCancel, 7); advance(40000); assert(f.count == 0 && f.server.authenticated);

    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7); advance(900);
    assert(f.count == 1 && f.held);
    id_command(ClipboardCancel, 7); count = f.count;
    advance(40000); assert(f.count == count && !f.held && f.server.authenticated);

    reset(); hello(); upload(program, size, 0, 0); f.usb = false; id_command(ClipboardExecute, 7);
    assert(f.server.state == ClipboardJobWaitingUSB && f.response[1] == ClipboardWaitingUSB);
    advance(1000); assert(f.count == 0);
    f.usb = true; finish(); assert(f.count == 10);

    reset(); hello(); upload(program, size, 0, 0); f.usb = false; id_command(ClipboardExecute, 7);
    advance(30000); assert(f.server.state == ClipboardJobIdle && !f.count && !f.opened);
    f.usb = true; advance(2000); assert(f.count == 0);

    reset(); hello(); begin(program, size, 0, 0); advance(15000);
    assert(f.server.state == ClipboardJobIdle && !f.opened && !f.count);
    reset(); hello(); upload(program, size, 0, 0); advance(30000); assert(!f.opened && !f.count);

    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7); advance(900);
    clipboard_server_tick(&f.server, f.now, false);
    assert(!f.server.authenticated && !f.opened && !f.held);
    count = f.count; id_command(ClipboardExecute, 7); advance(5000); assert(f.count == count);

    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7); advance(900);
    f.usb = false; advance(4); assert(!f.opened && !f.held && f.response[1] == ClipboardError);

    for(unsigned failure = 0; failure < 6; failure++) {
        reset(); hello();
        if(failure == 0) f.fail_open = true;
        if(failure == 1) f.fail_layout = true;
        if(failure < 2) { begin(program, size, 0, 0); assert(f.response[1] == ClipboardError && !f.opened); }
        else if(failure == 2) {
            begin(program, size, 0, 0); f.fail_write = true;
            uint8_t bytes[520]; clipboard_write_u32(bytes, 7); clipboard_write_u32(bytes + 4, 0); memcpy(bytes + 8, program, size);
            send_command(ClipboardChunk, bytes, size + 8); assert(!f.opened && !f.count);
        } else {
            upload(program, size, 0, 0);
            if(failure == 3) f.fail_read = true;
            if(failure == 4) f.fail_press = true;
            if(failure == 5) f.fail_send = true;
            id_command(ClipboardExecute, 7); advance(1000); assert(!f.opened && !f.held && !f.count);
        }
    }
    reset(); hello(); begin(program, size, 0, 0);
    uint8_t bytes[520]; clipboard_write_u32(bytes, 7); clipboard_write_u32(bytes + 4, 1); memcpy(bytes + 8, program, size);
    send_command(ClipboardChunk, bytes, size + 8); assert(!f.opened && !f.count);
    reset(); hello(); begin(program, size, 0, 0); id_command(ClipboardCommit, 7);
    assert(f.response[1] == ClipboardError && !f.opened);
    reset(); hello(); begin(program, size, 0, 0);
    clipboard_write_u32(bytes, 7); clipboard_write_u32(bytes + 4, 0); memcpy(bytes + 8, program, size); bytes[8] ^= 1;
    send_command(ClipboardChunk, bytes, size + 8); id_command(ClipboardCommit, 7);
    assert(f.response[1] == ClipboardError && !f.opened && !f.count);
    reset(); hello(); const uint8_t old[] = {2, 1, 0, 0}; clipboard_server_feed(&f.server, old, sizeof(old), f.now);
    assert(!f.server.authenticated && !f.count);
    reset(); hello(); const uint8_t oversized[] = {4, 2, 255, 255}; clipboard_server_feed(&f.server, oversized, sizeof(oversized), f.now);
    assert(!f.server.authenticated && !f.count);
}

static void program_checks(void) {
    uint8_t program[128];
    size_t size = text_program(program, (const uint8_t*)"a", 1);
    for(size_t truncated = 0; truncated < size; truncated++) {
        reset(); open_store(&f, size); write_store(&f, 0, program, size);
        ClipboardReader reader = {&f, truncated, read_store}; uint16_t layout[128]; us_layout(layout);
        assert(clipboard_program_validate(&reader, layout, false) != ClipboardProgramOk);
    }
    for(unsigned mutation = 0; mutation < 8; mutation++) {
        size = text_program(program, (const uint8_t*)"a", 1);
        if(mutation == 0) program[0] = 0;
        if(mutation == 1) program[4] = 129;
        if(mutation == 2) program[6] = 9;
        if(mutation == 3) program[7] = 255;
        if(mutation == 4) program[11] = 0x1B;
        if(mutation == 5) program[11] = 0xFF;
        if(mutation == 6) { program[6] = 2; program[7] = 0x80; program[8] = 'a'; program[9] = 0; size = 10; }
        if(mutation == 7) { program[6] = 3; clipboard_write_u32(program + 7, 30001); size = 11; }
        reset(); hello(); upload(program, size, 0, 0);
        assert(f.response[1] == ClipboardError && !f.opened && !f.count);
    }
    size = text_program(program, (const uint8_t*)"\xC4\x9F", 2);
    reset(); hello(); upload(program, size, 0, 0); assert(f.response[1] == ClipboardError && !f.count);
    reset(); hello(); upload(program, size, 1, 0); assert(f.response[1] == ClipboardVerified);
    id_command(ClipboardExecute, 7); finish(); assert(f.count == 1 && f.keys[0] == 0x2F);

    size = text_program(program, (const uint8_t*)"a\r\nb\rc\t", 7);
    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7); finish();
    assert(f.count == 6 && f.keys[1] == 0x28 && f.keys[3] == 0x28 && f.keys[5] == 0x2B);

    for(unsigned target = 0; target < 3; target++) for(unsigned layout = 0; layout < 28; layout++) {
        size = text_program(program, (const uint8_t*)"a", 1);
        reset(); hello(); upload(program, size, layout, target); assert(f.response[1] == ClipboardVerified);
        id_command(ClipboardCancel, 7); assert(!f.opened);
    }

    uint32_t random = 12345;
    uint16_t layout[128]; us_layout(layout);
    for(unsigned round = 0; round < 3000; round++) {
        reset(); size = 6 + round % (sizeof(program) - 6);
        for(size_t i = 0; i < size; i++) { random = random * 1664525U + 1013904223U; program[i] = random >> 24; }
        if(round & 1) memcpy(program, "BCM4", 4);
        open_store(&f, size); write_store(&f, 0, program, size);
        ClipboardReader reader = {&f, size, read_store};
        (void)clipboard_program_validate(&reader, layout, false);
        assert(f.count == 0);
    }
}

static void interruption_checks(void) {
    uint8_t program[6000];
    size_t size = text_program(program, (const uint8_t*)"before", 6);
    clipboard_write_u16(program + 4, 3);
    program[size++] = 3; clipboard_write_u32(program + size, 30000); size += 4;
    program[size++] = 1; clipboard_write_u32(program + size, 5); size += 4;
    memcpy(program + size, "AFTER", 5); size += 5;
    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7);
    advance(1200); assert(f.count == 6 && f.server.state == ClipboardJobRunning);
    unsigned messages = f.messages[ClipboardProgress];
    advance(5000); assert(f.count == 6 && f.messages[ClipboardProgress] > messages);
    id_command(ClipboardCancel, 7); advance(40000);
    assert(f.count == 6 && !f.held && !f.opened && f.server.authenticated);

    size = text_program(program, (const uint8_t*)"`a", 2);
    reset(); hello(); upload(program, size, 1, 0); id_command(ClipboardExecute, 7);
    advance(900); assert(f.count == 1 && f.held);
    id_command(ClipboardCancel, 7); advance(5000);
    assert(f.count == 1 && !f.held); // Stop never types a dead-key finisher after cancellation.

    uint8_t text[5000]; memset(text, 'x', sizeof(text));
    size = text_program(program, text, sizeof(text));
    reset(); hello(); begin(program, size, 0, 0);
    uint8_t chunk[520]; clipboard_write_u32(chunk, 7); clipboard_write_u32(chunk + 4, 0);
    memcpy(chunk + 8, program, 512); send_command(ClipboardChunk, chunk, sizeof(chunk));
    assert(f.ever_sd && f.opened && !f.count);
    id_command(ClipboardCancel, 7); advance(30000);
    assert(!f.opened && !f.count && f.server.authenticated);

    size = text_program(program, (const uint8_t*)"before", 6);
    clipboard_write_u16(program + 4, 2); program[size++] = 99;
    reset(); hello(); upload(program, size, 0, 0);
    assert(f.response[1] == ClipboardError && f.count == 0 && !f.opened);

    size = text_program(program, text, 100);
    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7);
    advance(900); assert(f.count == 1);
    f.fail_send = true; advance(252);
    unsigned count = f.count;
    assert(count < 100 && !f.held && !f.opened && !f.server.authenticated);
    advance(5000); assert(f.count == count);

    uint32_t random = 42;
    for(unsigned round = 0; round < 1000; round++) {
        reset(); size = 1 + round % 512;
        uint8_t bytes[512];
        for(size_t i = 0; i < size; i++) { random = random * 1664525U + 1013904223U; bytes[i] = random >> 24; }
        if(round & 1) bytes[0] = 4;
        for(size_t i = 0; i < size; i++) clipboard_server_feed(&f.server, bytes + i, 1, f.now++);
        clipboard_server_tick(&f.server, f.now, true);
        assert(f.count == 0 && f.server.frame_size < CLIPBOARD_FRAME_MAX);
    }
}

static size_t mouse_program(uint8_t* program, uint32_t duration, uint32_t interval) {
    memcpy(program, "BCM4", 4); clipboard_write_u16(program + 4, 1); program[6] = 4;
    clipboard_write_u32(program + 7, duration); clipboard_write_u32(program + 11, interval);
    return 15;
}

static void standalone_checks(void) {
    uint8_t program[64];
    size_t size = mouse_program(program, 8U * 3600000U, 60000);
    reset(); f.now = UINT32_MAX - 1500; hello();
    upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE); id_command(ClipboardExecute, 7);
    advance(904); assert(f.server.engine.mouse_active && f.mouse_count == 1 && f.count == 0);
    advance(56); assert(f.mouse_balance == 0 && f.mouse_count == 2);
    clipboard_server_disconnect(&f.server);
    assert(f.server.state == ClipboardJobRunning && f.opened && !f.server.authenticated);
    uint32_t duration = 8U * 3600000U + 1000;
    for(uint32_t elapsed = 0; elapsed < duration; elapsed += 1000) {
        f.now += 1000; clipboard_server_tick(&f.server, f.now, false);
    }
    assert(f.server.state == ClipboardJobIdle && !f.opened && f.count == 0 && f.mouse_count > 900);
    unsigned moved = f.mouse_count;
    f.now += 100000; clipboard_server_tick(&f.server, f.now, false);
    assert(f.mouse_count == moved); // Completion never schedules another run.

    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(904); moved = f.mouse_count;
    clipboard_server_disconnect(&f.server); clipboard_server_cancel(&f.server);
    f.now += 3600000; clipboard_server_tick(&f.server, f.now, false);
    assert(f.mouse_count == moved && f.count == 0 && !f.opened); // No return movement after physical Stop.

    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(904);
    clipboard_server_disconnect(&f.server);
    send_command(ClipboardHello, (const uint8_t*)"BLECLIP/4", 9);
    assert(f.server.authenticated && f.response[1] == ClipboardActive && clipboard_read_u32(f.response + 4) == 7);
    assert(clipboard_read_u32(f.response + 16) > 0);
    id_command(ClipboardCancel, 7); assert(!f.opened && f.server.state == ClipboardJobIdle);

    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7); advance(904);
    moved = f.mouse_count; clipboard_server_disconnect(&f.server);
    f.now += 3600000; clipboard_server_tick(&f.server, f.now, false);
    assert(f.mouse_count == moved && !f.opened); // Normal Mac-controlled runs still cancel.

    for(unsigned failure = 0; failure < 2; failure++) {
        reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
        id_command(ClipboardExecute, 7); advance(904);
        clipboard_server_disconnect(&f.server);
        if(failure == 0) f.usb = false; else f.fail_mouse = true;
        for(unsigned n = 0; n < 100; n++) { f.now += 4; clipboard_server_tick(&f.server, f.now, false); }
        assert(!f.opened && f.server.state == ClipboardJobIdle);
        moved = f.mouse_count; f.usb = true; f.fail_mouse = false;
        f.now += 3600000; clipboard_server_tick(&f.server, f.now, false);
        assert(f.mouse_count == moved);
    }
    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(904); f.fail_send = true; advance(252);
    assert(f.server.state == ClipboardJobRunning && !f.server.authenticated);
    clipboard_server_cancel(&f.server); assert(!f.opened);

    for(unsigned invalid = 0; invalid < 4; invalid++) {
        size = mouse_program(program, invalid == 0 ? 0 : invalid == 1 ? CLIPBOARD_MOUSE_MAX_MS + 1 : 60000,
                             invalid == 2 ? 0 : invalid == 3 ? 3600001 : 1000);
        reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
        assert(f.response[1] == ClipboardError && f.mouse_count == 0 && !f.opened);
    }
}

static void saved_checks(void) {
    uint8_t program[64], payload[64];
    size_t size = text_program(program, (const uint8_t*)"Saved [ENTER]", 13);
    clipboard_write_u32(payload, 7); memset(payload + 4, 1, 16); payload[20] = 5; memcpy(payload + 21, "Saved", 5);
    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_SAVE_ONLY);
    advance(1000); assert(f.count == 0 && f.mouse_count == 0);
    send_command(ClipboardSave, payload, 26);
    assert(f.saved && f.response[1] == ClipboardSavedReply && f.server.state == ClipboardJobIdle && !f.opened && !f.count);
    ClipboardSaved saved = f.saved_metadata;
    clipboard_server_disconnect(&f.server);
    open_store(&f, saved.size); write_store(&f, 0, f.saved_storage, saved.size);
    assert(clipboard_server_run_saved(&f.server, &saved, 9, f.now));
    for(unsigned tick = 0; tick < 2000 && f.server.state != ClipboardJobIdle; tick++) {
        f.now += 4; clipboard_server_tick(&f.server, f.now, false);
    }
    assert(f.count == 13 && f.server.state == ClipboardJobIdle && !f.opened);

    open_store(&f, saved.size); write_store(&f, 0, f.saved_storage, saved.size); f.storage[11] ^= 1;
    unsigned count = f.count;
    assert(!clipboard_server_run_saved(&f.server, &saved, 10, f.now) && f.count == count);
    close_store(&f);
    open_store(&f, saved.size); write_store(&f, 0, f.saved_storage, saved.size); f.usb = false;
    assert(!clipboard_server_run_saved(&f.server, &saved, 10, f.now)); close_store(&f);
    f.usb = true; f.now += 40000; clipboard_server_tick(&f.server, f.now, false);
    assert(f.count == count);

    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_SAVE_ONLY); f.fail_save = true;
    send_command(ClipboardSave, payload, 26);
    assert(!f.saved && f.response[1] == ClipboardError && !f.opened && !f.count);
    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_SAVE_ONLY);
    id_command(ClipboardExecute, 7); assert(!f.opened && !f.count && !f.saved);

    uint8_t header[CLIPBOARD_SAVED_HEADER]; ClipboardSaved decoded;
    assert(clipboard_saved_encode(&saved, header) && clipboard_saved_decode(header, &decoded));
    for(unsigned i = 0; i < sizeof(header); i++) {
        header[i] ^= 1; assert(!clipboard_saved_decode(header, &decoded)); header[i] ^= 1;
    }
    strcpy(saved.name, "bad\nname"); assert(!clipboard_saved_encode(&saved, header));
}

static size_t ranged_program(uint8_t* program, uint32_t duration, uint32_t low, uint32_t high) {
    memcpy(program, "BCM4", 4); clipboard_write_u16(program + 4, 1); program[6] = 6;
    clipboard_write_u32(program + 7, duration); clipboard_write_u32(program + 11, low);
    clipboard_write_u32(program + 15, high); clipboard_write_u16(program + 19, 1);
    clipboard_write_u32(program + 21, 5);
    program[25] = 5; program[26] = (uint8_t)-2; program[27] = 2; program[28] = (uint8_t)-2; program[29] = 2;
    return 30;
}

static void ranged_checks(void) {
    uint8_t program[256]; size_t size = ranged_program(program, 20000, 1000, 3000);
    reset(); f.now = UINT32_MAX - 1500; hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(904);
    assert(f.server.engine.repeat_active && f.mouse_count == 1 && !f.count);
    clipboard_server_disconnect(&f.server);
    for(unsigned elapsed = 0; elapsed < 22000; elapsed += 4) {
        f.now += 4; clipboard_server_tick(&f.server, f.now, false);
    }
    assert(f.server.state == ClipboardJobIdle && !f.opened && !f.count && f.mouse_count > 5 && f.mouse_count <= 21);
    bool varied_move = false, varied_interval = false;
    for(unsigned i = 0; i < f.mouse_count; i++) {
        assert(f.mouse_dx[i] >= -2 && f.mouse_dx[i] <= 2 && f.mouse_dy[i] >= -2 && f.mouse_dy[i] <= 2);
        assert(f.mouse_dx[i] || f.mouse_dy[i]);
        varied_move |= f.mouse_dx[i] != f.mouse_dx[0] || f.mouse_dy[i] != f.mouse_dy[0];
        if(i) {
            uint32_t interval = f.mouse_at[i] - f.mouse_at[i - 1];
            assert(interval >= 996 && interval <= 3004);
            if(i > 1) varied_interval |= interval != f.mouse_at[1] - f.mouse_at[0];
        }
    }
    assert(varied_move && varied_interval);

    // Eight simulated hours, with per-cycle sampling and no Bluetooth connection.
    size = ranged_program(program, 8U * 3600000U, 45000, 95000);
    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(904); clipboard_server_disconnect(&f.server);
    for(uint32_t elapsed = 0; elapsed < 8U * 3600000U + 1000; elapsed += 8) {
        f.now += 8; clipboard_server_tick(&f.server, f.now, false);
    }
    assert(f.server.state == ClipboardJobIdle && !f.opened && !f.count && f.mouse_count >= 300 && f.mouse_count <= 641);

    for(unsigned edge = 0; edge < 2; edge++) {
        size = ranged_program(program, 2000, 1000, 1000);
        reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
        f.forced_random = true; f.forced_value = edge ? UINT32_MAX : 0;
        id_command(ClipboardExecute, 7); finish();
        assert(f.mouse_count == 2 && f.mouse_dx[0] == (edge ? 2 : -2) && f.mouse_dy[0] == (edge ? 2 : -2));
    }

    for(unsigned failure = 0; failure < 3; failure++) {
        size = ranged_program(program, 30000, 1000, 3000);
        reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
        id_command(ClipboardExecute, 7); advance(904); clipboard_server_disconnect(&f.server);
        if(failure == 0) clipboard_server_cancel(&f.server);
        if(failure == 1) f.usb = false;
        if(failure == 2) f.fail_random = true;
        unsigned moved = f.mouse_count;
        for(unsigned elapsed = 0; elapsed < 35000; elapsed += 8) {
            f.now += 8; clipboard_server_tick(&f.server, f.now, false);
        }
        assert(f.server.state == ClipboardJobIdle && !f.opened && f.mouse_count == moved);
        f.usb = true; f.fail_random = false; f.now += 40000; clipboard_server_tick(&f.server, f.now, false);
        assert(f.mouse_count == moved);
    }

    // A fixed move needs no random value, even when entropy acquisition fails.
    size = ranged_program(program, 2000, 1000, 1000);
    program[26] = program[27] = 1; program[28] = program[29] = 0;
    reset(); hello(); upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    f.fail_random = true; id_command(ClipboardExecute, 7); finish();
    assert(f.mouse_count == 2 && f.mouse_dx[0] == 1 && f.mouse_dy[0] == 0);

    // Finishing a repeat releases a held key and executes its tail exactly once.
    size = ranged_program(program, 10, 1000, 1000);
    clipboard_write_u16(program + 4, 2); clipboard_write_u32(program + 21, 4);
    program[25] = 2; program[26] = 0; clipboard_write_u16(program + 27, 'a'); size = 29;
    program[size++] = 1; clipboard_write_u32(program + size, 1); size += 4; program[size++] = 'Z';
    reset(); hello(); upload(program, size, 0, 0); id_command(ClipboardExecute, 7); finish();
    assert(f.count == 2 && f.keys[0] == 4 && f.keys[1] == (0x200 | 29) && !f.held);

    for(unsigned invalid = 0; invalid < 6; invalid++) {
        size = ranged_program(program, 10000, 1000, 3000);
        if(invalid == 0) program[26] = 128;
        if(invalid == 1) program[26] = 3;
        if(invalid == 2) memset(program + 26, 0, 4);
        if(invalid == 3) clipboard_write_u32(program + 15, 999);
        if(invalid == 4) clipboard_write_u32(program + 21, 1);
        if(invalid == 5) { program[25] = 3; clipboard_write_u32(program + 26, 50); }
        reset(); hello(); upload(program, size, 0, 0);
        assert(f.response[1] == ClipboardError && !f.mouse_count && !f.count && !f.opened);
    }
}

static void companion_info_checks(void) {
    reset();
    send_command(ClipboardInfo, NULL, 0);
    assert(!f.server.authenticated && f.response[1] == ClipboardError && !f.count && !f.mouse_count);
    hello();
    unsigned releases = f.releases;
    send_command(ClipboardInfo, NULL, 0);
    assert(f.response[1] == ClipboardInfoReply && f.response_size == 17 && f.response[4] == 1);
    assert(clipboard_read_u16(f.response + 5) == CLIPBOARD_APP_VERSION_MAJOR);
    assert(clipboard_read_u16(f.response + 7) == CLIPBOARD_APP_VERSION_MINOR);
    assert(clipboard_read_u16(f.response + 9) == CLIPBOARD_APP_VERSION_PATCH);
    assert(f.response[11] == 4 && clipboard_read_u16(f.response + 12) == 88 &&
           clipboard_read_u16(f.response + 14) == 2 && f.response[16] == 7);
    assert(f.server.state == ClipboardJobIdle && f.releases == releases && !f.opened);

    uint8_t program[64]; size_t size = ranged_program(program, 10000, 1000, 3000);
    upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(920);
    assert(f.server.state == ClipboardJobRunning);
    uint32_t cursor = f.server.engine.cursor, end = f.server.engine.repeat_end, due = f.server.engine.due;
    unsigned moved = f.mouse_count; releases = f.releases;
    send_command(ClipboardInfo, NULL, 0);
    assert(f.response[1] == ClipboardInfoReply && f.server.state == ClipboardJobRunning);
    assert(f.server.engine.cursor == cursor && f.server.engine.repeat_end == end && f.server.engine.due == due);
    assert(f.mouse_count == moved && f.releases == releases && f.count == 0);
    const uint8_t invalid = 1;
    send_command(ClipboardInfo, &invalid, 1);
    assert(f.response[1] == ClipboardError && f.server.state == ClipboardJobRunning);
    assert(f.server.engine.cursor == cursor && f.mouse_count == moved && f.releases == releases);
    clipboard_server_cancel(&f.server);
}

static void keyboard_settings_checks(void) {
    reset();
    uint8_t get[2] = {1, 0}, set[10] = {2, 0, 1, 1, 0, 1};
    send_command(ClipboardGetKeyboard, get, sizeof(get));
    assert(f.response[1] == ClipboardError && !f.keyboard_saves);
    hello();
    clipboard_server_keyboard_changed(&f.server);
    assert(!f.messages[ClipboardKeyboardReply]); // Legacy clients never receive a new response unsolicited.
    unsigned releases = f.releases;
    send_command(ClipboardGetKeyboard, get, sizeof(get));
    assert(f.response[1] == ClipboardKeyboardReply && f.response_size == 15);
    assert(clipboard_read_u16(f.response + 5) == 1 && f.response[7] == ClipboardKeyboardOk);
    assert(!f.keyboard_saves && !f.count && !f.mouse_count && f.releases == releases);
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardOk && f.server.keyboard_settings.layout == 1);
    assert(f.server.keyboard_settings.override_saved && f.server.keyboard_settings.revision == 1);
    assert(f.keyboard_saves == 1 && f.persisted_keyboard.layout == 1 && !f.count && !f.mouse_count);
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardConflict && f.keyboard_saves == 1);
    clipboard_write_u32(set + 6, 1);
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardOk && f.keyboard_saves == 1 && f.server.keyboard_settings.revision == 1);
    set[3] = 27; set[4] = 2;
    f.fail_layout = true;
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardUnavailable && f.server.keyboard_settings.layout == 1);
    f.fail_layout = false; f.fail_keyboard_save = true;
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardSaveFailed && f.server.keyboard_settings.revision == 1);
    f.fail_keyboard_save = false;
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardOk && f.server.keyboard_settings.layout == 27);
    set[3] = 28; clipboard_write_u32(set + 6, 2);
    send_command(ClipboardSetKeyboard, set, sizeof(set)); assert(f.response[7] == ClipboardKeyboardInvalid);
    set[3] = 1; set[4] = 3;
    send_command(ClipboardSetKeyboard, set, sizeof(set)); assert(f.response[7] == ClipboardKeyboardInvalid);
    set[4] = 0; set[5] = 2;
    send_command(ClipboardSetKeyboard, set, sizeof(set)); assert(f.response[7] == ClipboardKeyboardInvalid);
    set[5] = 1;
    send_command(ClipboardSetKeyboard, set, sizeof(set) - 1); assert(f.response[7] == ClipboardKeyboardInvalid);

    clipboard_server_disconnect(&f.server);
    assert(f.server.keyboard_settings.layout == 27 && f.server.keyboard_settings.revision == 2);
    assert(!f.server.keyboard_subscribed);
    hello();
    unsigned messages = f.messages[ClipboardKeyboardReply];
    clipboard_server_keyboard_changed(&f.server); assert(f.messages[ClipboardKeyboardReply] == messages);
    send_command(ClipboardGetKeyboard, get, sizeof(get));
    ClipboardKeyboardSettings local = f.server.keyboard_settings; local.layout = 1; local.target = 0;
    assert(clipboard_server_set_keyboard(&f.server, local) == ClipboardKeyboardOk);
    clipboard_server_keyboard_changed(&f.server);
    assert(clipboard_read_u16(f.response + 5) == 0 && f.response[8] == 1);

    uint8_t program[64]; size_t size = ranged_program(program, 10000, 1000, 3000);
    upload_mode(program, size, 0, 0, CLIPBOARD_STANDALONE);
    id_command(ClipboardExecute, 7); advance(920);
    uint32_t cursor = f.server.engine.cursor, end = f.server.engine.repeat_end, due = f.server.engine.due;
    unsigned moved = f.mouse_count, keys = f.count; releases = f.releases;
    send_command(ClipboardGetKeyboard, get, sizeof(get));
    clipboard_write_u32(set + 6, f.server.keyboard_settings.revision);
    send_command(ClipboardSetKeyboard, set, sizeof(set));
    assert(f.response[7] == ClipboardKeyboardBusy && f.server.state == ClipboardJobRunning);
    assert(f.server.engine.cursor == cursor && f.server.engine.repeat_end == end && f.server.engine.due == due);
    assert(f.mouse_count == moved && f.count == keys && f.releases == releases);
    clipboard_server_disconnect(&f.server);
    assert(f.server.state == ClipboardJobRunning && f.server.keyboard_settings.layout == 1);
    clipboard_server_cancel(&f.server);
    f.server.keyboard_settings.revision = UINT32_MAX;
    local.revision = UINT32_MAX;
    assert(clipboard_server_set_keyboard(&f.server, local) == ClipboardKeyboardConflict);

    // A local override uses the selected map, while the saved record remains original.
    reset(); hello();
    size = text_program(program, (const uint8_t*)"i", 1);
    ClipboardSaved saved = {.layout = 0, .target = 0, .size = (uint32_t)size};
    saved.id[0] = 1; strcpy(saved.name, "Original US");
    saved.crc = clipboard_crc_update(0xFFFFFFFFU, program, size) ^ 0xFFFFFFFFU;
    assert(open_store(&f, size) && write_store(&f, 0, program, size));
    local = (ClipboardKeyboardSettings){.layout = 1, .override_saved = true, .revision = 1};
    ClipboardSaved run = clipboard_saved_for_keyboard(&saved, &local);
    assert(clipboard_server_run_saved(&f.server, &run, 90, f.now));
    advance(2996); assert(!f.count);
    finish(); assert(f.count == 1 && f.keys[0] == clipboard_turkish_mac['i']);
    assert(saved.layout == 0 && run.layout == 1 && saved.crc == run.crc);
    reset(); hello();
    size = text_program(program, (const uint8_t*)"\xc3\xa7", 2);
    saved.size = (uint32_t)size; saved.layout = 1;
    saved.crc = clipboard_crc_update(0xFFFFFFFFU, program, size) ^ 0xFFFFFFFFU;
    assert(open_store(&f, size) && write_store(&f, 0, program, size));
    local.layout = 2;
    run = clipboard_saved_for_keyboard(&saved, &local);
    assert(!clipboard_server_run_saved(&f.server, &run, 91, f.now));
    assert(!f.count && f.server.state == ClipboardJobIdle && saved.layout == 1);
    close_store(&f);
}

static void map_reports(void) {
    printf("[");
    bool first = true;
    const uint32_t native[] = {0xC7, 0xD6, 0xDC, 0xE7, 0xF6, 0xFC, 0x11E, 0x11F, 0x130, 0x131, 0x15E, 0x15F};
    for(unsigned i = 0; i < 107; i++) {
        uint32_t scalar = i < 95 ? i + 32 : native[i - 95];
        uint8_t text[2]; size_t length = scalar < 128 ? 1 : 2;
        if(length == 1) text[0] = scalar;
        else { text[0] = 0xC0 | (scalar >> 6); text[1] = 0x80 | (scalar & 0x3F); }
        uint8_t program[13]; size_t size = text_program(program, text, length);
        reset(); hello(); upload(program, size, 1, 0); assert(f.response[1] == ClipboardVerified);
        id_command(ClipboardExecute, 7); finish();
        assert(f.count == (scalar == '`' ? 2U : 1U));
        printf("%s{\"ascii\":%u,\"keys\":[", first ? "" : ",", scalar); first = false;
        for(unsigned key = 0; key < f.count; key++) printf("%s%u", key ? "," : "", f.keys[key]);
        printf("]}");
    }
    puts("]");
}

static void swift_fixtures(const char* directory) {
    const char* names[] = {"literal", "turkish", "large", "macro", "jiggle", "saved"};
    for(unsigned i = 0; i < 6; i++) {
        char path[1024]; snprintf(path, sizeof(path), "%s/%s.wire", directory, names[i]);
        FILE* file = fopen(path, "rb"); assert(file);
        uint8_t* wire = malloc(100000); size_t size = fread(wire, 1, 100000, file); assert(size && size < 100000); fclose(file);
        reset();
        for(size_t offset = 0; offset < size;) {
            size_t count = size - offset; if(count > 128) count = 128;
            clipboard_server_feed(&f.server, wire + offset, count, f.now++); offset += count;
        }
        free(wire);
        if(i == 5) {
            assert(f.server.state == ClipboardJobIdle && f.saved && !f.opened && !f.count && !f.mouse_count);
            assert(strcmp(f.saved_metadata.name, "Saved Snapshot") == 0);
            assert(f.response[1] == ClipboardSavedReply);
            continue;
        }
        assert(f.server.state == ClipboardJobRunning && f.count == 0);
        finish(); assert(f.messages[ClipboardDone] == 1 && f.response[8] == 0);
        if(i == 0) {
            assert(f.count == strlen("Literal [ENTER] [GUI+r] [] {{clipboard}}"));
            for(unsigned j = 0; j < f.count; j++) assert((f.keys[j] & 0x9900) == 0);
        } else if(i == 1) {
            const uint32_t native[] = {0xE7, 0xC7, 0x11F, 0x11E, 0x131, 0x130, 0xF6, 0xD6, 0x15F, 0x15E, 0xFC, 0xDC, 0x15F, 0x130};
            assert(f.count == 14);
            for(unsigned j = 0; j < 14; j++) assert(f.keys[j] == clipboard_turkish_hid(native[j]));
        } else if(i == 2) assert(f.count == 65525 && f.ever_sd && f.messages[ClipboardProgress] > 0);
        else if(i == 3) assert(f.count == 13 && f.keys[5] == 0x0804 && f.keys[6] == 0x2B);
        else assert(f.count == 0 && f.mouse_count == 2);
    }
    char path[1024]; snprintf(path, sizeof(path), "%s/keyboard.wire", directory);
    FILE* file = fopen(path, "rb"); assert(file);
    uint8_t wire[128]; size_t size = fread(wire, 1, sizeof(wire), file); fclose(file);
    assert(size && size < sizeof(wire)); reset();
    for(size_t i = 0; i < size; i++) clipboard_server_feed(&f.server, wire + i, 1, f.now++);
    assert(f.server.keyboard_settings.layout == 1 && f.server.keyboard_settings.target == 2);
    assert(f.server.keyboard_settings.override_saved && f.server.keyboard_settings.revision == 1);
    assert(!f.count && !f.mouse_count && !f.releases && !f.opened);
    snprintf(path, sizeof(path), "%s/keyboard.reply", directory);
    file = fopen(path, "rb"); assert(file);
    size = fread(wire, 1, sizeof(wire), file); fclose(file);
    assert(size == f.response_size && memcmp(wire, f.response, size) == 0);
}

static void typing_checks(void) {
    uint8_t program[] = {'B','C','M','4',2,0,7,80,0,30,0,1,2,0,0,0,'a','b'};
    const unsigned invalid[][2] = {{1001,0},{20,21},{900,101}};
    for(unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        clipboard_write_u16(program + 7, invalid[i][0]); clipboard_write_u16(program + 9, invalid[i][1]);
        reset(); hello(); upload(program, sizeof(program), 0, 0); assert(f.response[1] == ClipboardError && !f.count);
    }
    clipboard_write_u16(program + 7, 1000); clipboard_write_u16(program + 9, 0);
    for(unsigned loss = 0; loss < 3; loss++) {
        reset(); f.now = UINT32_MAX - 1000; hello(); upload(program, sizeof(program), 0, 0);
        assert(f.response[1] == ClipboardVerified); id_command(ClipboardExecute, 7); advance(916);
        assert(f.count == 1 && !f.held);
        if(loss == 0) id_command(ClipboardCancel, 7);
        else if(loss == 1) f.usb = false;
        else clipboard_server_tick(&f.server, f.now, false);
        advance(2000); assert(f.count == 1 && !f.held && !f.opened);
    }
    reset(); hello(); upload(program, sizeof(program), 0, 0); id_command(ClipboardExecute, 7);
    advance(920); assert(f.count == 1); advance(988); assert(f.count == 1); finish(); assert(f.count == 2);
    clipboard_write_u16(program + 7, 80); clipboard_write_u16(program + 9, 30);
    reset(); hello(); upload(program, sizeof(program), 0, 0); f.fail_random = true; id_command(ClipboardExecute, 7);
    finish(); assert(f.response[1] == ClipboardError && f.count == 1 && !f.held);
    uint8_t misplaced[] = {'B','C','M','4',2,0,1,1,0,0,0,'x',7,80,0,0,0};
    reset(); hello(); upload(misplaced, sizeof(misplaced), 0, 0); assert(f.response[1] == ClipboardError && !f.count);
}

static void interop_fixtures(const char* directory) {
    for(unsigned i = 0; i < 5; i++) {
        char path[1024]; snprintf(path, sizeof(path), "%s/interop-%u.wire", directory, i);
        FILE* file = fopen(path, "rb"); assert(file);
        uint8_t wire[4096]; size_t size = fread(wire, 1, sizeof(wire), file); fclose(file);
        assert(size && size < sizeof(wire)); reset();
        for(size_t offset = 0; offset < size; offset++) clipboard_server_feed(&f.server, wire + offset, 1, f.now++);
        assert(f.server.state == ClipboardJobRunning && !f.count && !f.mouse_count);
        finish(); assert(f.messages[ClipboardDone] == 1 && f.response[8] == 0);
        assert(f.count || f.mouse_count);
    }
}

int main(int argc, char** argv) {
    if(argc == 2 && strcmp(argv[1], "--map") == 0) { map_reports(); return 0; }
    if(argc == 3 && strcmp(argv[1], "--interop") == 0) { interop_fixtures(argv[2]); return 0; }
    assert((clipboard_crc_update(0xFFFFFFFFU, (const uint8_t*)"123456789", 9) ^ 0xFFFFFFFFU) == 0xCBF43926);
    protocol_checks(); program_checks(); interruption_checks(); standalone_checks(); saved_checks(); ranged_checks(); companion_info_checks(); keyboard_settings_checks(); typing_checks();
    if(argc == 2) swift_fixtures(argv[1]);
    puts("Independent v4 transfer / typed macro engine / cancellation / failures / fuzz checks passed");
    return 0;
}
