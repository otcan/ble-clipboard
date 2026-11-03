// Link the actual Info-only app without any Bluetooth, HID or storage symbols.
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <furi.h>
#include <gui/gui.h>
#include "../../BluetoothClipboard/clipboard_screen.h"

struct FuriMessageQueue { size_t index; };
struct FuriMutex { bool locked; };
struct Gui { int unused; };
struct ViewPort { void (*draw)(Canvas*, void*); void* context; };
static unsigned allocations, records, seen, draws;
static Gui gui;
FuriMessageQueue* furi_message_queue_alloc(size_t count, size_t size) {
    assert(count == 8 && size == sizeof(InputEvent)); allocations++;
    return calloc(1, sizeof(FuriMessageQueue));
}
void furi_message_queue_free(FuriMessageQueue* p) { allocations--; free(p); }
int furi_message_queue_put(FuriMessageQueue* p, const void* e, uint32_t timeout) {
    (void)p; (void)e; assert(timeout == 0); return FuriStatusOk;
}
int furi_message_queue_get(FuriMessageQueue* p, void* output, uint32_t timeout) {
    static const int keys[] = {InputKeyOk, InputKeyBack, InputKeyLeft};
    assert(timeout == FuriWaitForever && p->index < 3);
    *(InputEvent*)output = (InputEvent){InputTypePress, keys[p->index++]};
    return FuriStatusOk;
}
FuriMutex* furi_mutex_alloc(int type) {
    assert(type == FuriMutexTypeNormal); allocations++; return calloc(1, sizeof(FuriMutex));
}
void furi_mutex_free(FuriMutex* p) { assert(!p->locked); allocations--; free(p); }
int furi_mutex_acquire(FuriMutex* p, uint32_t timeout) {
    assert(timeout == FuriWaitForever && !p->locked); p->locked = true; return FuriStatusOk;
}
void furi_mutex_release(FuriMutex* p) { assert(p->locked); p->locked = false; }
void* furi_record_open(const char* name) { assert(strcmp(name, RECORD_GUI) == 0); records++; return &gui; }
void furi_record_close(const char* name) { assert(strcmp(name, RECORD_GUI) == 0 && records == 1); records--; }
ViewPort* view_port_alloc(void) { allocations++; return calloc(1, sizeof(ViewPort)); }
void view_port_free(ViewPort* p) { allocations--; free(p); }
void view_port_draw_callback_set(ViewPort* p, void (*cb)(Canvas*, void*), void* context) {
    p->draw = cb; p->context = context;
}
void view_port_input_callback_set(ViewPort* p, void (*cb)(InputEvent*, void*), void* context) {
    assert(p && cb && context == p->context);
}
void view_port_update(ViewPort* p) { Canvas canvas = {0}; p->draw(&canvas, p->context); }
void gui_add_view_port(Gui* g, ViewPort* p, int layer) {
    assert(g == &gui && layer == GuiLayerFullscreen); view_port_update(p);
}
void gui_remove_view_port(Gui* g, ViewPort* p) { assert(g == &gui && p); }
void clipboard_screen_info(ClipboardScreen* s, bool qr) { memset(s, 0, sizeof(*s)); s->companion_qr = qr; }
void clipboard_screen_draw(Canvas* c, const ClipboardScreen* s) {
    assert(c); seen |= s->companion_qr ? 2 : 1; draws++;
}
int main(void) {
    assert(clipboard_info_app() == 0);
    assert(allocations == 0 && records == 0 && seen == 3 && draws == 4);
    puts("Info-only app: GUI-only link / About-QR-Back-exit / balanced cleanup checks passed");
}
