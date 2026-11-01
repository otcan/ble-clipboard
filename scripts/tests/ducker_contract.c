// Reuse upstream's fake USB harness; compile against the pinned production engine.
#define main upstream_hid_checks
#include "../../Vendor/Ducker/tests/test_hid.c"
#undef main

int main(void) {
    reset(8);
    const char* literal = "[]ENTER]";
    assert(ttf_hid_send_string(literal, strlen(literal)));
    assert(presses == 7 && last_key == 0x30);
    reset(8);
    file_text = literal;
    assert(ttf_hid_send_file("/fake/payload.tmp", strlen(literal)));
    assert(presses == 7 && last_key == 0x30);
    reset(8);
    assert(ttf_hid_send_string("[WIN+a]", 7));
    assert(presses == 1 && last_key == 0x0804); // Command+A without Shift.
    reset(8);
    assert(ttf_hid_send_string("[CTRL+a]", 8));
    assert(presses == 1 && last_key == 0x0104);
    puts("Mac serialization / production HID contract checks passed");
    return 0;
}
