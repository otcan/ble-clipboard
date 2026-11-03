#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <u8g2.h>

typedef struct { u8g2_t fb; uint8_t pixels[1024]; } Canvas;
typedef enum { ColorWhite, ColorBlack } Color;
typedef enum { FontSecondary } Font;
typedef enum { AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom } Align;
void canvas_clear(Canvas*);
void canvas_set_color(Canvas*, Color);
void canvas_set_font(Canvas*, Font);
void canvas_draw_str(Canvas*, int32_t, int32_t, const char*);
void canvas_draw_str_aligned(Canvas*, int32_t, int32_t, Align, Align, const char*);
void canvas_draw_line(Canvas*, int32_t, int32_t, int32_t, int32_t);
void canvas_draw_box(Canvas*, int32_t, int32_t, size_t, size_t);
void canvas_draw_xbm(Canvas*, int32_t, int32_t, size_t, size_t, const uint8_t*);
