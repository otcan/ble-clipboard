#pragma once
#include "canvas.h"
#include <input/input.h>
typedef struct Gui Gui;
typedef struct ViewPort ViewPort;
enum { GuiLayerFullscreen };
ViewPort* view_port_alloc(void);
void view_port_free(ViewPort*);
void view_port_draw_callback_set(ViewPort*, void (*)(Canvas*, void*), void*);
void view_port_input_callback_set(ViewPort*, void (*)(InputEvent*, void*), void*);
void view_port_update(ViewPort*);
void gui_add_view_port(Gui*, ViewPort*, int);
void gui_remove_view_port(Gui*, ViewPort*);
