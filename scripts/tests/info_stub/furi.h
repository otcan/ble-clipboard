#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef struct FuriMessageQueue FuriMessageQueue;
typedef struct FuriMutex FuriMutex;
enum { FuriStatusOk, FuriMutexTypeNormal };
#define FuriWaitForever UINT32_MAX
#define RECORD_GUI "gui"
FuriMessageQueue* furi_message_queue_alloc(size_t, size_t);
void furi_message_queue_free(FuriMessageQueue*);
int furi_message_queue_put(FuriMessageQueue*, const void*, uint32_t);
int furi_message_queue_get(FuriMessageQueue*, void*, uint32_t);
FuriMutex* furi_mutex_alloc(int);
void furi_mutex_free(FuriMutex*);
int furi_mutex_acquire(FuriMutex*, uint32_t);
void furi_mutex_release(FuriMutex*);
void* furi_record_open(const char*);
void furi_record_close(const char*);
