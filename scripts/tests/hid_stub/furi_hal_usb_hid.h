#pragma once

#include <stdbool.h>
#include <stdint.h>

bool furi_hal_hid_kb_release_all(void);
bool furi_hal_hid_mouse_release(uint8_t buttons);
bool furi_hal_hid_mouse_move(int8_t dx, int8_t dy);
