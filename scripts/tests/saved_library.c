#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "../../BluetoothClipboard/clipboard_library.h"
#include "../../BluetoothClipboard/transfer_protocol.h"
#include "../../BluetoothClipboard/keyboard_settings_store.h"

struct File { Storage* storage; FILE* file; DIR* directory; };
File* storage_file_alloc(Storage* storage) {
    File* file = calloc(1, sizeof(*file)); assert(file); file->storage = storage; storage->allocations++; return file;
}
bool storage_file_close(File* file) { if(file->file) { fclose(file->file); file->file = NULL; } return true; }
bool storage_dir_close(File* file) { if(file->directory) { closedir(file->directory); file->directory = NULL; } return true; }
void storage_file_free(File* file) {
    assert(!file->file && !file->directory); file->storage->allocations--; free(file);
}
bool storage_file_open(File* file, const char* path, FS_AccessMode access, FS_OpenMode mode) {
    (void)access; assert(!file->file); file->file = fopen(path, mode == FSOM_CREATE_ALWAYS ? "w+b" : "rb"); return file->file != NULL;
}
bool storage_file_is_dir(File* file) { struct stat info; return fstat(fileno(file->file), &info) == 0 && S_ISDIR(info.st_mode); }
uint64_t storage_file_size(File* file) { struct stat info; assert(fstat(fileno(file->file), &info) == 0); return (uint64_t)info.st_size; }
uint16_t storage_file_read(File* file, void* output, uint16_t size) { return (uint16_t)fread(output, 1, size, file->file); }
uint16_t storage_file_write(File* file, const void* input, uint16_t size) {
    if(file->storage->fail_write) return 0;
    return (uint16_t)fwrite(input, 1, size, file->file);
}
bool storage_file_seek(File* file, uint32_t offset, bool from_start) { return fseek(file->file, offset, from_start ? SEEK_SET : SEEK_CUR) == 0; }
bool storage_file_sync(File* file) { return !file->storage->fail_sync && fflush(file->file) == 0; }
bool storage_file_exists(Storage* storage, const char* path) { (void)storage; struct stat info; return stat(path, &info) == 0 && S_ISREG(info.st_mode); }
bool storage_dir_exists(Storage* storage, const char* path) { (void)storage; struct stat info; return stat(path, &info) == 0 && S_ISDIR(info.st_mode); }
bool storage_dir_open(File* file, const char* path) { file->directory = opendir(path); return file->directory != NULL; }
bool storage_dir_read(File* file, FileInfo* info, char* name, uint16_t size) {
    (void)info; struct dirent* entry = readdir(file->directory);
    if(!entry) return false;
    snprintf(name, size, "%s", entry->d_name); return true;
}
bool storage_simply_remove(Storage* storage, const char* path) { (void)storage; return unlink(path) == 0 || errno == ENOENT; }
bool storage_simply_mkdir(Storage* storage, const char* path) {
    // FatFs rejects trailing separators, unlike the host's POSIX filesystem.
    size_t length = strlen(path);
    if(!length || path[length - 1] == '/') return false;
    return mkdir(path, 0700) == 0 || (errno == EEXIST && storage_dir_exists(storage, path));
}
FS_Error storage_common_rename(Storage* storage, const char* from, const char* to) {
    storage->rename_count++;
    if(storage->fail_rename == storage->rename_count || access(to, F_OK) == 0) return FSE_INTERNAL;
    return rename(from, to) == 0 ? FSE_OK : FSE_INTERNAL;
}

static uint8_t data[CLIPBOARD_PROGRAM_MAX], loaded[CLIPBOARD_PROGRAM_MAX];
static bool read_memory(void* context, size_t offset, uint8_t* output, size_t size) { memcpy(output, (uint8_t*)context + offset, size); return true; }
static bool write_memory(void* context, size_t offset, const uint8_t* input, size_t size) { memcpy((uint8_t*)context + offset, input, size); return true; }
static ClipboardSaved metadata(unsigned id, size_t size) {
    ClipboardSaved saved = {.layout = 0, .target = 0, .size = (uint32_t)size};
    saved.id[0] = (uint8_t)id; snprintf(saved.name, sizeof(saved.name), "Saved %02u", id);
    saved.crc = clipboard_crc_update(0xFFFFFFFFU, data, size) ^ 0xFFFFFFFFU;
    return saved;
}
static void paths(const ClipboardSaved* saved, char final[128], char backup[128], char temporary[128]) {
    char id[33]; clipboard_saved_id(saved->id, id);
    snprintf(final, 128, "library/saved/%s.bcm", id); snprintf(backup, 128, "library/saved/%s.bak", id);
    snprintf(temporary, 128, "library/saved/%s.tmp", id);
}
static void file_copy(const char* from, const char* to) {
    FILE* input = fopen(from, "rb"); FILE* output = fopen(to, "wb"); assert(input && output);
    uint8_t bytes[256]; size_t size;
    while((size = fread(bytes, 1, sizeof(bytes), input)) != 0) assert(fwrite(bytes, 1, size, output) == size);
    fclose(input); fclose(output);
}
static void corrupt(const char* path, long offset) {
    FILE* file = fopen(path, "r+b"); assert(file && fseek(file, offset, SEEK_SET) == 0);
    int byte = fgetc(file); assert(byte != EOF); assert(fseek(file, offset, SEEK_SET) == 0);
    fputc(byte ^ 1, file); fclose(file);
}
static void assert_loaded(ClipboardLibrary* library, const ClipboardSaved* saved, const uint8_t* expected) {
    memset(loaded, 0, sizeof(loaded));
    assert(clipboard_library_load(library, saved, loaded, write_memory));
    assert(memcmp(loaded, expected, saved->size) == 0);
    assert(library->storage->allocations == 0);
}

static void keyboard_settings_checks(Storage* storage) {
    ClipboardKeyboardSettings settings, old = {.layout = 1, .target = 0, .override_saved = true, .revision = 1};
    assert(!clipboard_keyboard_settings_load(storage, &settings));
    assert(!settings.override_saved && settings.layout == 0 && settings.revision == 0);
    assert(clipboard_keyboard_settings_save(storage, &old));
    assert(clipboard_keyboard_settings_load(storage, &settings) && settings.layout == 1 && settings.override_saved && settings.revision == 1);
    ClipboardKeyboardSettings next = {.layout = 27, .target = 2, .revision = 2};
    for(unsigned failure = 0; failure < 4; failure++) {
        storage->rename_count = 0; storage->fail_rename = failure >= 2 ? failure - 1 : 0;
        storage->fail_write = failure == 0; storage->fail_sync = failure == 1;
        assert(!clipboard_keyboard_settings_save(storage, &next));
        storage->fail_write = storage->fail_sync = false; storage->fail_rename = 0;
        assert(clipboard_keyboard_settings_load(storage, &settings) && settings.revision == 1 && settings.layout == 1);
    }
    const char* final = "library/.keyboard-v1", *backup = "library/.keyboard-v1.bak";
    assert(rename(final, backup) == 0);
    assert(clipboard_keyboard_settings_load(storage, &settings) && settings.revision == 1);
    assert(access(backup, F_OK) != 0);
    assert(clipboard_keyboard_settings_save(storage, &next));
    assert(clipboard_keyboard_settings_load(storage, &settings) && settings.layout == 27 && settings.target == 2 && !settings.override_saved);
    file_copy(final, backup); corrupt(final, 4);
    assert(clipboard_keyboard_settings_load(storage, &settings) && settings.revision == 2);
    assert(access(backup, F_OK) != 0);
    corrupt(final, 0);
    assert(!clipboard_keyboard_settings_load(storage, &settings));
    assert(!settings.revision && !settings.override_saved); // No unverified staging promotion or English override.
    corrupt(final, 0);
    settings = next; settings.layout = 28; assert(!clipboard_keyboard_settings_save(storage, &settings));
    settings = next; settings.target = 3; assert(!clipboard_keyboard_settings_save(storage, &settings));
    settings = next; settings.revision = 0; assert(!clipboard_keyboard_settings_save(storage, &settings));
    assert(clipboard_keyboard_settings_load(storage, &settings) && settings.revision == 2 && settings.layout == 27);

    ClipboardSaved snapshot = metadata(99, 14);
    uint8_t before[CLIPBOARD_SAVED_HEADER], after[CLIPBOARD_SAVED_HEADER];
    assert(clipboard_saved_encode(&snapshot, before));
    ClipboardSaved run = clipboard_saved_for_keyboard(&snapshot, &old);
    assert(run.layout == 1 && run.target == 0 && run.size == snapshot.size && run.crc == snapshot.crc);
    assert(clipboard_saved_encode(&snapshot, after) && memcmp(before, after, sizeof(before)) == 0);
    run = clipboard_saved_for_keyboard(&snapshot, &next);
    assert(run.layout == snapshot.layout && run.target == snapshot.target);
    assert(storage->allocations == 0);
    puts("Keyboard SD settings: restart / rollback / interrupted replace / corruption / unchanged snapshots checks passed");
}

int main(void) {
    Storage storage = {0}; ClipboardLibrary library = {.storage = &storage};
    assert(!storage_simply_mkdir(&storage, APP_DATA_PATH("")));
    clipboard_library_refresh(&library); assert(library.count == 0 && storage.allocations == 0);
    memcpy(data, "BCM4\1\0\1\3\0\0\0old", 14);
    ClipboardReader reader = {data, 14, read_memory};
    ClipboardSaved old = metadata(1, reader.size);
    assert(clipboard_library_save(&library, &old, &reader) && library.count == 1);
    assert(storage_dir_exists(&storage, STORAGE_APP_DATA_PATH_PREFIX));
    uint8_t original[14]; memcpy(original, data, sizeof(original));
    assert_loaded(&library, &old, original);
    char final[128], backup[128], temporary[128]; paths(&old, final, backup, temporary);
    memcpy(data + 11, "new", 3); ClipboardSaved next = metadata(1, reader.size);
    for(unsigned failure = 0; failure < 4; failure++) {
        storage.rename_count = 0; storage.fail_rename = failure >= 2 ? failure - 1 : 0;
        storage.fail_write = failure == 0; storage.fail_sync = failure == 1;
        assert(!clipboard_library_save(&library, &next, &reader));
        storage.fail_write = storage.fail_sync = false; storage.fail_rename = 0;
        clipboard_library_refresh(&library);
        assert(library.count == 1); assert_loaded(&library, &old, original);
    }

    // Power loss between renames must recover the previous committed file, never the staged file.
    assert(rename(final, backup) == 0);
    clipboard_library_refresh(&library); assert_loaded(&library, &old, original);
    assert(access(backup, F_OK) != 0 && access(temporary, F_OK) == 0);
    assert(clipboard_library_save(&library, &next, &reader)); assert_loaded(&library, &next, data);
    assert(access(backup, F_OK) != 0);

    // An invalid final file plus a valid recovery copy restores the recovery copy.
    file_copy(final, backup); corrupt(final, CLIPBOARD_SAVED_HEADER + 11);
    clipboard_library_refresh(&library); assert_loaded(&library, &next, data);
    file_copy(final, backup); clipboard_library_refresh(&library);
    assert(access(backup, F_OK) != 0); assert_loaded(&library, &next, data);
    corrupt(final, CLIPBOARD_SAVED_HEADER + 11);
    assert(!clipboard_library_load(&library, &next, loaded, write_memory));
    corrupt(final, CLIPBOARD_SAVED_HEADER + 11);
    corrupt(final, 4); clipboard_library_refresh(&library); assert(library.count == 0);
    corrupt(final, 4); clipboard_library_refresh(&library); assert(library.count == 1);

    // The real limit is 20 entries; replacing an existing UUID does not consume another slot.
    for(unsigned id = 2; id <= CLIPBOARD_SAVED_LIMIT; id++) {
        ClipboardSaved saved = metadata(id, reader.size);
        assert(clipboard_library_save(&library, &saved, &reader));
    }
    assert(library.count == CLIPBOARD_SAVED_LIMIT);
    ClipboardSaved extra = metadata(21, reader.size);
    assert(!clipboard_library_save(&library, &extra, &reader));
    assert(clipboard_library_save(&library, &next, &reader));
    file_copy(final, backup);
    assert(clipboard_library_remove(&library, &next));
    clipboard_library_refresh(&library); assert(library.count == CLIPBOARD_SAVED_LIMIT - 1);
    assert(access(final, F_OK) != 0 && access(backup, F_OK) != 0 && access(temporary, F_OK) != 0);

    // A maximum-size program is copied and verified in bounded chunks, not a large stack allocation.
    memset(data, 'x', sizeof(data)); memcpy(data, "BCM4\1\0\1", 7);
    clipboard_write_u32(data + 7, sizeof(data) - 11);
    reader.size = sizeof(data); extra = metadata(21, reader.size);
    assert(clipboard_library_save(&library, &extra, &reader)); assert_loaded(&library, &extra, data);
    ClipboardLibrary restarted = {.storage = &storage}; clipboard_library_refresh(&restarted);
    assert(restarted.count == CLIPBOARD_SAVED_LIMIT && storage.allocations == 0);
    assert_loaded(&restarted, &extra, data);
    keyboard_settings_checks(&storage);
    puts("Saved SD library: persistence / 20-slot limit / atomic replace / recovery / corruption / bounded copy checks passed");
    return 0;
}
