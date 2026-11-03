#pragma once
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdio.h>
typedef struct { char text[128]; } FuriString;
static inline FuriString* furi_string_alloc(void) { return calloc(1, sizeof(FuriString)); }
static inline void furi_string_set_strn(FuriString* s, const char* text, size_t size) {
    assert(size < sizeof(s->text));
    memcpy(s->text, text, size); s->text[size] = 0;
}
static inline const char* furi_string_get_cstr(FuriString* s) { return s->text; }
static inline void furi_string_free(FuriString* s) { free(s); }
