// Host-only canvas adapter, matching official firmware 1.5.1 canvas/elements.
// No BLE, storage, USB, input injection or device API is linked into this tool.
#include "gui/elements.h"
#include "clipboard_screen.h"
#include "companion_version.h"
#include "button_icons.h"
#include <stdio.h>

void canvas_clear(Canvas* c) { u8g2_ClearBuffer(&c->fb); }
void canvas_set_color(Canvas* c, Color color) { u8g2_SetDrawColor(&c->fb, color); }
void canvas_set_font(Canvas* c, Font font) {
    (void)font;
    u8g2_SetFontMode(&c->fb, 1);
    u8g2_SetFont(&c->fb, u8g2_font_haxrcorp4089_tr);
}
void canvas_draw_str(Canvas* c, int32_t x, int32_t y, const char* s) {
    u8g2_DrawUTF8(&c->fb, x, y, s);
}
void canvas_draw_str_aligned(Canvas* c, int32_t x, int32_t y, Align h, Align v, const char* s) {
    assert(v == AlignBottom);
    if(h == AlignCenter) x -= u8g2_GetUTF8Width(&c->fb, s) / 2;
    else if(h == AlignRight) x -= u8g2_GetUTF8Width(&c->fb, s);
    canvas_draw_str(c, x, y, s);
}
void canvas_draw_line(Canvas* c, int32_t x, int32_t y, int32_t xx, int32_t yy) {
    u8g2_DrawLine(&c->fb, x, y, xx, yy);
}
void canvas_draw_box(Canvas* c, int32_t x, int32_t y, size_t w, size_t h) {
    u8g2_DrawBox(&c->fb, x, y, w, h);
}
void canvas_draw_xbm(Canvas* c, int32_t x, int32_t y, size_t w, size_t h, const uint8_t* bits) {
    u8g2_DrawXBM(&c->fb, x, y, w, h, bits);
}
void elements_string_fit_width(Canvas* c, FuriString* s, size_t width) {
    if(u8g2_GetUTF8Width(&c->fb, s->text) <= width) return;
    width -= u8g2_GetUTF8Width(&c->fb, "...");
    while(u8g2_GetUTF8Width(&c->fb, s->text) > width) s->text[strlen(s->text) - 1] = 0;
    strcat(s->text, "...");
}
static void button(Canvas* c, const char* text, int position) {
    int iw = position == 0 ? 7 : 4;
    int padding = position == 0 ? 1 : 3;
    int width = u8g2_GetUTF8Width(&c->fb, text) + padding * 2 + iw + 3;
    int x = position < 0 ? 0 : position > 0 ? 128 - width : (128 - width) / 2;
    canvas_draw_box(c, x, 52, width, 12);
    for(int i = 0; i < 3; i++) {
        if(position >= 0) canvas_draw_line(c, x - i - 1, 64, x - i - 1, 52 + i);
        if(position <= 0) canvas_draw_line(c, x + width + i, 64, x + width + i, 52 + i);
    }
    c->fb.draw_color = !c->fb.draw_color;
    if(position > 0) {
        canvas_draw_str(c, x + padding, 61, text);
        canvas_draw_xbm(c, 128 - padding - iw, 54, iw, 7, button_right);
    } else {
        canvas_draw_xbm(c, x + padding, 54, iw, 7, position < 0 ? button_left : button_center);
        canvas_draw_str(c, x + padding + iw + 3, 61, text);
    }
    c->fb.draw_color = !c->fb.draw_color;
}
void elements_button_left(Canvas* c, const char* s) { button(c, s, -1); }
void elements_button_center(Canvas* c, const char* s) { button(c, s, 0); }
void elements_button_right(Canvas* c, const char* s) { button(c, s, 1); }

int main(int argc, char** argv) {
    assert(argc == 2);
    static const u8x8_display_info_t display = {
        .tile_width = 16, .tile_height = 8, .pixel_width = 128, .pixel_height = 64,
    };
    Canvas canvas = {0};
    canvas.fb.u8x8.display_info = &display;
    u8g2_SetupBuffer(&canvas.fb, canvas.pixels, 8, u8g2_ll_hvline_vertical_top_lsb, U8G2_R0);
    assert(strcmp(argv[1], "downloads") == 0 || strcmp(argv[1], "info") == 0);
    ClipboardScreen screen;
    clipboard_screen_info(&screen, strcmp(argv[1], "downloads") == 0);
    clipboard_screen_draw(&canvas, &screen);
    return fwrite(canvas.pixels, 1, sizeof(canvas.pixels), stdout) == sizeof(canvas.pixels) ? 0 : 1;
}
