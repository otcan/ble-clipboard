#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define APP_DATA_PATH(path) "library/" path
typedef struct {
    unsigned rename_count, fail_rename;
    bool fail_write, fail_sync;
    unsigned allocations;
} Storage;
typedef struct File File;
typedef struct { unsigned flags; } FileInfo;
typedef enum { FSAM_READ, FSAM_WRITE } FS_AccessMode;
typedef enum { FSOM_OPEN_EXISTING, FSOM_CREATE_ALWAYS } FS_OpenMode;
typedef enum { FSE_OK, FSE_NOT_EXIST, FSE_INTERNAL } FS_Error;
File* storage_file_alloc(Storage* storage);
void storage_file_free(File* file);
bool storage_file_open(File* file, const char* path, FS_AccessMode access, FS_OpenMode mode);
bool storage_file_close(File* file);
bool storage_file_is_dir(File* file);
uint64_t storage_file_size(File* file);
uint16_t storage_file_read(File* file, void* output, uint16_t size);
uint16_t storage_file_write(File* file, const void* input, uint16_t size);
bool storage_file_seek(File* file, uint32_t offset, bool from_start);
bool storage_file_sync(File* file);
bool storage_file_exists(Storage* storage, const char* path);
bool storage_dir_open(File* file, const char* path);
bool storage_dir_close(File* file);
bool storage_dir_exists(Storage* storage, const char* path);
bool storage_dir_read(File* file, FileInfo* info, char* name, uint16_t size);
bool storage_simply_remove(Storage* storage, const char* path);
bool storage_simply_mkdir(Storage* storage, const char* path);
FS_Error storage_common_rename(Storage* storage, const char* from, const char* to);
