#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/Store/dist"
mkdir -p "$OUT"
git -C "$ROOT" archive --format=tar.gz --output="$OUT/ble-clipboard-source.tar.gz" HEAD
git -C "$ROOT/Vendor/Ducker" archive --format=tar.gz --output="$OUT/ducker-source.tar.gz" HEAD
printf '%s\n' 'Source archives contain the committed project and pinned Ducker source, not local build products or secrets.'
