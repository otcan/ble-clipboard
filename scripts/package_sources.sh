#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-"$ROOT/Store/dist/ble-clipboard-source.tar.gz"}
mkdir -p "$(dirname -- "$OUT")"
# Snapshot this build's allowlisted source, including uncommitted development work.
tar --exclude='*/dist' --exclude='*/.build' --exclude='*/build' --exclude='*/.vscode' \
    --exclude='*/.venv*' \
    --exclude='*.keys' --exclude='*.key' --exclude='*.pem' --exclude='*.p12' \
    --exclude='*.mobileprovision' --exclude='*.env' --exclude='*.env.*' \
    --exclude='*/__pycache__' --exclude='*.pyc' --exclude='*.DS_Store' \
    -czf "$OUT" -C "$ROOT" \
    BLEClipboardMac/Sources BLEClipboardMac/Tests BLEClipboardMac/Resources \
    BLEClipboardMac/Package.swift BLEClipboardMac/build_app.sh BLEClipboardMac/README.md \
    BLEClipboardWindows/ble_clipboard BLEClipboardWindows/tests BLEClipboardWindows/resources \
    BLEClipboardWindows/packaging BLEClipboardWindows/launch.py BLEClipboardWindows/build.ps1 \
    BLEClipboardWindows/requirements.txt BLEClipboardWindows/requirements-build.txt BLEClipboardWindows/README.md \
    BluetoothClipboard scripts docs packaging .github .gitignore .gitattributes \
    Store/project.yml Store/Info.plist Store/Store.entitlements Store/PrivacyInfo.xcprivacy \
    Store/UITests Store/HardwareTests Store/metadata Store/README.md \
    VERSION README.md NOTICE LICENSE CHANGELOG.md SECURITY.md CONTRIBUTING.md
printf 'Current independent project source: %s\n' "$OUT"
