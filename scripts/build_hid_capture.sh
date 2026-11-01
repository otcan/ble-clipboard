#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/Store/dist/BT Paste USB Capture.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 5 -framework AppKit "$ROOT/Store/HardwareTests/HIDCapture.swift" -o "$APP/Contents/MacOS/HIDCapture"
cp "$ROOT/Store/HardwareTests/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
