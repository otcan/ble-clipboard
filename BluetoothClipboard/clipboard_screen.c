#include "clipboard_screen.h"

#include <furi.h>
#include <gui/elements.h>
#include <string.h>

static void draw_status_line(Canvas* canvas, const char* text, size_t length, int32_t baseline) {
    FuriString* line = furi_string_alloc();
    furi_string_set_strn(line, text, length);
    elements_string_fit_width(canvas, line, 120);
    canvas_draw_str_aligned(
        canvas, 64, baseline, AlignCenter, AlignBottom, furi_string_get_cstr(line));
    furi_string_free(line);
}

void clipboard_screen_draw(Canvas* canvas, const char* status) {
    const char* detail = strchr(status, '\n');
    size_t title_length = detail ? (size_t)(detail - status) : strlen(status);

    canvas_clear(canvas);
    canvas_set_color(canvas, ColorBlack);
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str(canvas, 4, 10, "BLE Clipboard");
    canvas_draw_line(canvas, 0, 14, 127, 14);

    // Reserve separate bands for the title, detail, and native exit control.
    canvas_set_font(canvas, FontPrimary);
    draw_status_line(canvas, status, title_length, 32);
    canvas_set_font(canvas, FontSecondary);
    if(detail) {
        detail++;
        draw_status_line(canvas, detail, strcspn(detail, "\n"), 45);
    }
    elements_button_left(canvas, "Exit");
}
