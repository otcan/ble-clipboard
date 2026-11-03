#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT/BluetoothClipboard"
"${UFBT:-ufbt}"
OUT="$ROOT/BluetoothClipboard/dist"
shasum -a 256 ./*.c ./*.h application.fam icon.png dist/ble_clipboard.fap > "$OUT/BUILD-SOURCE-SHA256SUMS.txt"
tar --exclude='./dist' --exclude='./.vscode' --exclude='*.keys' \
    -czf "$OUT/ble-clipboard-flipper-source.tar.gz" -C "$ROOT/BluetoothClipboard" .
printf 'Independent Flipper app and corresponding source: %s\n' "$OUT"
