#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/Store/dist"
mkdir -p "$OUT"
STAGE=$(mktemp -d "$OUT/ducker-compat.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
git -C "$ROOT/Vendor/Ducker" archive HEAD | tar -x -C "$STAGE"
mv "$STAGE/trans_the_flip_bt.c" "$STAGE/upstream_bt.inc"
cp "$ROOT/DuckerCompatibility/trans_the_flip_bt.c" "$STAGE/trans_the_flip_bt.c"
cp "$ROOT/DuckerCompatibility/bt_paste_serial_proxy.h" "$STAGE/bt_paste_serial_proxy.h"
cp "$ROOT/DuckerCompatibility/application.fam" "$STAGE/application.fam"
cp "$ROOT/DuckerCompatibility/BUILD.md" "$STAGE/BT-PASTE-COMPATIBILITY.md"
(cd "$STAGE" && "${UFBT:-ufbt}")
cp "$STAGE/dist/bt_paste_ducker_compat.fap" "$OUT/bt_paste_ducker_compat.fap"
tar --exclude='./dist' --exclude='./.vscode' -czf "$OUT/bt-paste-ducker-compat-source.tar.gz" -C "$STAGE" .
printf 'Compatibility FAP and complete source: %s\n' "$OUT"
