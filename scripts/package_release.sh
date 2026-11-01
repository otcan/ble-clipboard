#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
version=${1:-$(<"$root/VERSION")}
[[ "$version" == <->.<->.<-> ]] || { print -u2 "Expected a numeric x.y.z version"; exit 2; }
out="$root/dist/v$version"
mkdir -p "$out"
APP_VERSION="$version" "$root/BLEClipboardMac/build_app.sh" --universal
[[ -f "$root/BluetoothClipboard/dist/ble_clipboard.fap" ]] || {
    print -u2 "Build BluetoothClipboard with ufbt before packaging."
    exit 1
}
ditto -c -k --sequesterRsrc --keepParent \
    "$root/BLEClipboardMac/dist/BLE Clipboard.app" "$out/BLE-Clipboard-$version-universal.zip"
cp "$root/BluetoothClipboard/dist/ble_clipboard.fap" "$out/ble_clipboard.fap"
cp "$root/LICENSE" "$out/LICENSE"
cp "$root/README.md" "$out/README.md"
cd "$out"
shasum -a 256 "BLE-Clipboard-$version-universal.zip" ble_clipboard.fap > SHA256SUMS.txt
print "Release artifacts: $out"
