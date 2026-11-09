#!/bin/zsh
set -euo pipefail
root=${0:A:h:h}
version=${1:-$(<"$root/VERSION")}
[[ "$version" == <->.<->.<-> ]] || { print -u2 "Expected a numeric x.y.z version"; exit 2; }
[[ "$version" == "$(<"$root/VERSION")" ]] || {
    print -u2 "Release version must match this source checkout. Older artifacts must not be rebuilt."
    exit 2
}
[[ -f "$root/BluetoothClipboard/dist/ble_clipboard.fap" && \
   -f "$root/BluetoothClipboard/dist/ble-clipboard-flipper-source.tar.gz" && \
   -f "$root/BluetoothClipboard/dist/BUILD-SOURCE-SHA256SUMS.txt" ]] || {
    print -u2 "Build the matching FAP and source with sh scripts/build_flipper.sh first."
    exit 1
}
(cd "$root/BluetoothClipboard" && shasum -a 256 -c dist/BUILD-SOURCE-SHA256SUMS.txt)
out="$root/dist/v$version"
windows="$root/BLEClipboardWindows/dist/v$version"
"${PYTHON:-python3}" "$root/scripts/release_assets.py" "$root/BLEClipboardWindows/dist" "$version" --windows-revision "$(git -C "$root" rev-parse HEAD)"
for name in "BLE-Clipboard-$version-windows-x64-setup.exe" "BLE-Clipboard-$version-windows-x64-portable.zip" WINDOWS-THIRD-PARTY.txt; do
    [[ -s "$windows/$name" ]] || { print -u2 "Missing reviewed Windows artifact: $name"; exit 1; }
done
swift "$root/scripts/generate_companion_assets.swift" --check
mkdir -p "$out"
APP_VERSION="$version" "$root/BLEClipboardMac/build_app.sh" --universal
ditto -c -k --sequesterRsrc --keepParent \
    "$root/BLEClipboardMac/dist/BLE Clipboard.app" "$out/BLE-Clipboard-$version-universal.zip"
cp "$root/BluetoothClipboard/dist/ble_clipboard.fap" "$out/ble_clipboard.fap"
cp "$root/BluetoothClipboard/dist/ble-clipboard-flipper-source.tar.gz" "$out/ble-clipboard-flipper-source.tar.gz"
cp "$root/BluetoothClipboard/dist/BUILD-SOURCE-SHA256SUMS.txt" "$out/FLIPPER-SOURCE-SHA256SUMS.txt"
sh "$root/scripts/package_sources.sh" "$out/ble-clipboard-source.tar.gz"
cp "$root/LICENSE" "$out/LICENSE"
cp "$root/NOTICE" "$out/NOTICE"
cp "$root/README.md" "$out/README.md"
cp "$windows/BLE-Clipboard-$version-windows-x64-setup.exe" "$windows/BLE-Clipboard-$version-windows-x64-portable.zip" "$windows/WINDOWS-THIRD-PARTY.txt" "$out/"
"${PYTHON:-python3}" "$root/scripts/release_assets.py" "$out" "$version"
print "Release artifacts: $out"
