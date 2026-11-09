#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../BluetoothClipboard/keyboard_menu.h"
#include "../../BluetoothClipboard/keyboard_layout.h"

int main(void) {
    ClipboardKeyboardMenu menu;
    ClipboardKeyboardSettings original = {.layout = 1, .target = 0, .override_saved = true, .revision = 9};
    ClipboardScreen screen;
    clipboard_keyboard_menu_init(&menu, original);
    clipboard_keyboard_menu_screen(&menu, &screen);
    assert(screen.selected == 0 && strstr(screen.lines[1], "Turkish Q"));
    assert(clipboard_keyboard_menu_input(&menu, InputKeyBack) == ClipboardKeyboardMenuBack);
    assert(clipboard_keyboard_menu_input(&menu, InputKeyUp) == ClipboardKeyboardMenuNone && menu.row == 0);
    clipboard_keyboard_menu_input(&menu, InputKeyOk); assert(menu.draft.target == 1);
    clipboard_keyboard_menu_input(&menu, InputKeyOk); assert(menu.draft.target == 2);
    clipboard_keyboard_menu_input(&menu, InputKeyOk); assert(menu.draft.target == 0);
    clipboard_keyboard_menu_input(&menu, InputKeyDown);
    clipboard_keyboard_menu_input(&menu, InputKeyOk); assert(menu.layouts);
    for(unsigned i = 0; i < 40; i++) clipboard_keyboard_menu_input(&menu, InputKeyUp);
    assert(menu.selected_layout == 0);
    for(unsigned i = 0; i < CLIPBOARD_LAYOUT_COUNT; i++) {
        clipboard_keyboard_menu_screen(&menu, &screen);
        assert(screen.selected >= 1 && screen.selected <= 3);
        assert(strcmp(screen.lines[screen.selected], clipboard_layout_titles[i]) == 0);
        clipboard_keyboard_menu_input(&menu, InputKeyDown);
    }
    assert(menu.selected_layout == 27);
    clipboard_keyboard_menu_input(&menu, InputKeyBack); assert(!menu.layouts && menu.draft.layout == 1);
    clipboard_keyboard_menu_input(&menu, InputKeyOk);
    clipboard_keyboard_menu_input(&menu, InputKeyDown);
    clipboard_keyboard_menu_input(&menu, InputKeyOk); assert(menu.draft.layout == 2 && !menu.layouts);
    clipboard_keyboard_menu_input(&menu, InputKeyDown);
    clipboard_keyboard_menu_input(&menu, InputKeyOk); assert(!menu.draft.override_saved);
    clipboard_keyboard_menu_input(&menu, InputKeyDown);
    clipboard_keyboard_menu_input(&menu, InputKeyDown); assert(menu.row == 3);
    clipboard_keyboard_menu_screen(&menu, &screen);
    assert(strcmp(screen.center, "Save") == 0 && strcmp(screen.left, "Back") == 0);
    assert(clipboard_keyboard_menu_input(&menu, InputKeyOk) == ClipboardKeyboardMenuSave);
    assert(original.layout == 1 && original.revision == 9 && menu.draft.revision == 9);
    puts("Keyboard menu: 28 choices / target / saved-run scope / explicit save / cancel checks passed");
    return 0;
}
