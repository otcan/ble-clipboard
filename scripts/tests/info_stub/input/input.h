#pragma once
enum { InputTypePress };
typedef enum { InputKeyUp, InputKeyDown, InputKeyRight, InputKeyLeft, InputKeyOk, InputKeyBack } InputKey;
typedef struct { int type; InputKey key; } InputEvent;
