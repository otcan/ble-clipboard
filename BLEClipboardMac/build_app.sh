#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app_dir="$project_dir/dist/BLE Clipboard.app"
version=${APP_VERSION:-$(<"$project_dir/../VERSION")}

cd "$project_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

if [[ ${1:-} == --universal ]]; then
    binaries=()
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx14.0"
        swift build -c release --triple "$triple" --scratch-path ".build/$arch"
        bin_dir=$(swift build -c release --triple "$triple" --scratch-path ".build/$arch" --show-bin-path)
        binaries+=("$bin_dir/BLEClipboardMac")
    done
    lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/BLEClipboardMac"
elif [[ $# == 0 ]]; then
    swift build -c release
    bin_dir=$(swift build -c release --show-bin-path)
    cp "$bin_dir/BLEClipboardMac" "$app_dir/Contents/MacOS/BLEClipboardMac"
else
    print -u2 "Usage: $0 [--universal]"
    exit 2
fi

"$project_dir/../scripts/build_icon.sh"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/../LICENSE" "$app_dir/Contents/Resources/LICENSE"
codesign --force --options runtime --sign "${CODE_SIGN_IDENTITY:--}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
