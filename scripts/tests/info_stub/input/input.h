#pragma once
enum { InputTypePress, InputKeyBack, InputKeyLeft, InputKeyOk };
typedef struct { int type; int key; } InputEvent;
