#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../BluetoothClipboard/clipboard_hid.h"

typedef struct {
    uint8_t buttons;
    int8_t dx, dy;
} MouseReport;

static struct {
    bool connected, fail_keyboard, fail_release, fail_move, key_held;
    uint8_t buttons, released_mask;
    unsigned keyboard_releases, mouse_releases, moves, reports;
    MouseReport report[8];
} hid;

static void reset(uint8_t buttons) {
    memset(&hid, 0, sizeof(hid));
    hid.connected = true;
    hid.buttons = buttons;
    hid.key_held = true;
}

bool furi_hal_hid_kb_release_all(void) {
    hid.keyboard_releases++;
    hid.key_held = false;
    return hid.connected && !hid.fail_keyboard;
}

bool furi_hal_hid_mouse_release(uint8_t buttons) {
    // Model firmware 1.5.1: buttons persist, and are cleared even when transmission fails.
    hid.mouse_releases++;
    hid.released_mask = buttons;
    hid.buttons &= (uint8_t)~buttons;
    if(!hid.connected || hid.fail_release) return false;
    assert(hid.reports < 8);
    hid.report[hid.reports++] = (MouseReport){hid.buttons, 0, 0};
    return true;
}

bool furi_hal_hid_mouse_move(int8_t dx, int8_t dy) {
    hid.moves++;
    if(!hid.connected || hid.fail_move) return false;
    assert(hid.reports < 8);
    hid.report[hid.reports++] = (MouseReport){hid.buttons, dx, dy};
    return true;
}

int main(void) {
    reset(1);
    assert(furi_hal_hid_mouse_move(2, -2));
    assert(hid.report[0].buttons == 1); // The old direct HAL call can drag with stale state.

    const uint8_t held[] = {0, 1, 2, 4, 7, 0x80, UINT8_MAX};
    for(size_t i = 0; i < sizeof(held); i++) {
        reset(held[i]);
        assert(clipboard_hid_mouse_move(-127, 127));
        assert(hid.mouse_releases == 1 && hid.released_mask == UINT8_MAX);
        assert(hid.moves == 1 && hid.reports == 2);
        assert(hid.report[0].buttons == 0 && hid.report[0].dx == 0 && hid.report[0].dy == 0);
        assert(hid.report[1].buttons == 0 && hid.report[1].dx == -127 && hid.report[1].dy == 127);
        hid.buttons = held[i];
        assert(clipboard_hid_mouse_move(2, -2));
        assert(hid.reports == 4 && hid.report[2].buttons == 0 && hid.report[2].dx == 0);
        assert(hid.report[3].buttons == 0 && hid.report[3].dx == 2 && hid.report[3].dy == -2);
    }

    reset(1);
    hid.fail_release = true;
    assert(!clipboard_hid_mouse_move(2, 2));
    assert(hid.buttons == 0 && hid.moves == 0 && hid.reports == 0);

    reset(1);
    hid.fail_move = true;
    assert(!clipboard_hid_mouse_move(2, 2));
    assert(hid.buttons == 0 && hid.moves == 1 && hid.reports == 1);
    assert(hid.report[0].buttons == 0 && hid.report[0].dx == 0 && hid.report[0].dy == 0);

    for(unsigned failure = 0; failure < 4; failure++) {
        reset(UINT8_MAX);
        hid.fail_keyboard = failure == 1;
        hid.fail_release = failure == 2;
        hid.connected = failure != 3;
        assert(clipboard_hid_release_all() == (failure == 0));
        assert(!hid.key_held && hid.buttons == 0 && hid.moves == 0);
        assert(hid.keyboard_releases == 1 && hid.mouse_releases == 1);
    }

    reset(UINT8_MAX);
    hid.connected = false;
    assert(!clipboard_hid_release_all()); // Startup before USB enumeration still clears inherited state.
    hid.connected = true;
    assert(clipboard_hid_mouse_move(1, 0));
    assert(hid.report[0].buttons == 0 && hid.report[1].buttons == 0);
    assert(clipboard_hid_release_all()); // Stop/exit emits only a neutral mouse report, no return motion.
    assert(hid.moves == 1 && hid.report[2].buttons == 0 && hid.report[2].dx == 0 && hid.report[2].dy == 0);
    puts("USB HID adapter: inherited-button drag / button-up-before-move / failure gating / neutral Stop checks passed");
    return 0;
}
