#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
if [ "$(uname -s)" = Darwin ]; then
    swift "$ROOT/scripts/generate_companion_assets.swift" --check
fi
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I"$ROOT/scripts/tests/info_stub" \
    "$ROOT/scripts/tests/clipboard_info.c" "$ROOT/BluetoothClipboard/clipboard_info.c" \
    -o "$BUILD/info-tests"
"$BUILD/info-tests"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I"$ROOT/scripts/tests/hid_stub" \
    "$ROOT/scripts/tests/clipboard_hid.c" -o "$BUILD/hid-tests"
"$BUILD/hid-tests"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$ROOT/scripts/tests/clipboard_layouts.c" -o "$BUILD/layouts"
"$BUILD/layouts"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I"$ROOT/scripts/tests/storage_stub" \
    "$ROOT/scripts/tests/saved_library.c" "$ROOT/BluetoothClipboard/clipboard_library.c" \
    "$ROOT/BluetoothClipboard/saved_program.c" "$ROOT/BluetoothClipboard/macro_engine.c" \
    "$ROOT/BluetoothClipboard/transfer_protocol.c" -o "$BUILD/library-tests"
(cd "$BUILD" && "$BUILD/library-tests")
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$ROOT/scripts/tests/independent_engine.c" "$ROOT/BluetoothClipboard/macro_engine.c" \
    "$ROOT/BluetoothClipboard/transfer_protocol.c" "$ROOT/BluetoothClipboard/saved_program.c" -o "$BUILD/engine"
CLIPBOARD_FIXTURE_DIR="$BUILD/fixtures" swift test --package-path "$ROOT/BLEClipboardMac" --filter ProgramFixtureTests
"$BUILD/engine" "$BUILD/fixtures"
"$BUILD/engine" --map > "$BUILD/keyboard-reports.json"
if [ "$(uname -s)" = Darwin ]; then
    swift "$ROOT/Store/HardwareTests/KeyboardLayoutProbe.swift" --verify "$BUILD/keyboard-reports.json"
fi
