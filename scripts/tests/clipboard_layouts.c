#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../BluetoothClipboard/keyboard_layout.h"
#include "../../BluetoothClipboard/keyboard_text.h"

int main(void) {
    assert(CLIPBOARD_LAYOUT_COUNT == 28 && clipboard_layout_files[0] == NULL);
    assert(strcmp(clipboard_layout_files[1], "tr-TR.kl") == 0);
    assert(strcmp(clipboard_layout_files[27], "sv-SE.kl") == 0);
    for(unsigned i = 1; i < CLIPBOARD_LAYOUT_COUNT; i++) {
        assert(strchr(clipboard_layout_files[i], '/') == NULL);
        assert(strlen(clipboard_layout_files[i]) < 32);
        for(unsigned j = i + 1; j < CLIPBOARD_LAYOUT_COUNT; j++) {
            assert(strcmp(clipboard_layout_files[i], clipboard_layout_files[j]) != 0);
        }
    }
    const uint8_t text[] = "\xC3\xA7\xC3\x87\xC4\x9F\xC4\x9E\xC4\xB1\xC4\xB0\xC3\xB6\xC3\x96\xC5\x9F\xC5\x9E\xC3\xBC\xC3\x9C";
    assert(clipboard_text_valid(text, sizeof(text) - 1, 1));
    for(unsigned layout = 0; layout < CLIPBOARD_LAYOUT_COUNT; layout++) {
        assert(clipboard_text_valid((const uint8_t*)"abc\r\n\t[]", strlen("abc\r\n\t[]"), layout));
        if(layout != 1) assert(!clipboard_text_valid(text, sizeof(text) - 1, layout));
    }
    size_t position = 0, count = 0;
    while(position < sizeof(text) - 1) {
        uint32_t scalar;
        assert(clipboard_text_next(text, sizeof(text) - 1, &position, &scalar));
        uint16_t key = clipboard_turkish_hid(scalar);
        assert(key != 0 && (key & 0xFD00) == 0); // Shift only, never Control/Alt/GUI.
        count++;
    }
    assert(count == 12);
    const uint8_t invalid[][4] = {
        {0xC4, 0, 0, 0}, {0xC0, 0xAF, 0, 0}, {0xC3, 0xE7, 0, 0},
        {0xED, 0xA0, 0x80, 0}, {0xC3, 0xA9, 0, 0}, {0xF0, 0x9F, 0x98, 0x80},
        {0, 0, 0, 0}, {0x1B, 0, 0, 0}, {0x7F, 0, 0, 0},
    };
    for(unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        assert(!clipboard_text_valid(invalid[i], sizeof(invalid[i]), 1));
    }
    assert(!clipboard_text_valid(text, 1, 1));
    assert(!clipboard_text_valid(text, 0, 1));
    puts("All 28 basic layout IDs / Turkish UTF-8 / malformed input checks passed");
    return 0;
}
