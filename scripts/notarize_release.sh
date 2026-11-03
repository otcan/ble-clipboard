#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
version=${1:-$(<"$root/VERSION")}
[[ "$version" == <->.<->.<-> ]] || { print -u2 "Expected a numeric x.y.z version"; exit 2; }
: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to your Developer ID Application certificate}"
: "${DEVELOPER_TEAM_ID:?Set DEVELOPER_TEAM_ID to your 10-character Apple team ID}"
[[ "$CODE_SIGN_IDENTITY" != - ]] || { print -u2 "Ad-hoc signatures cannot be notarized"; exit 2; }
[[ "$DEVELOPER_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || { print -u2 "Invalid Apple team ID"; exit 2; }

profile=${NOTARY_PROFILE:-ble-clipboard-notary}
app="$root/BLEClipboardMac/dist/BLE Clipboard.app"
out="$root/dist/v$version"
archive="$out/BLE-Clipboard-$version-universal.zip"
logs="$root/dist/notary-logs/v$version"

# Validate the existing Keychain profile before building; never print credentials.
xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
"$root/scripts/package_release.sh" "$version"
signature=$(codesign --display --verbose=4 "$app" 2>&1)
[[ "$signature" == *"Authority=Developer ID Application:"* ]] || {
    print -u2 "The app is not signed with a Developer ID Application certificate."
    exit 1
}
print -r -- "$signature" | grep -Fqx "TeamIdentifier=$DEVELOPER_TEAM_ID" || {
    print -u2 "The signing certificate does not match DEVELOPER_TEAM_ID."
    exit 1
}
lipo "$app/Contents/MacOS/BLEClipboardMac" -verify_arch arm64 x86_64
mkdir -p "$logs"

if ! xcrun notarytool submit "$archive" --keychain-profile "$profile" \
    --wait --timeout 30m --output-format json > "$logs/submission.json"; then
    print -u2 "Notarization did not complete. Check $logs/submission.json before retrying."
    exit 1
fi
notary_status=$(plutil -extract status raw -o - "$logs/submission.json")
[[ "$notary_status" == Accepted ]] || {
    print -u2 "Notarization status is $notary_status. No release was published. See $logs/submission.json."
    exit 1
}

xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"

# Stapling changes the bundle. Repack without rebuilding or re-signing it.
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
cd "$out"
shasum -a 256 "BLE-Clipboard-$version-universal.zip" ble_clipboard.fap \
    ble-clipboard-flipper-source.tar.gz ble-clipboard-source.tar.gz \
    FLIPPER-SOURCE-SHA256SUMS.txt README.md NOTICE LICENSE > SHA256SUMS.txt
print "Verified notarized artifacts: $out"
print "Generate the Homebrew cask from this archive, not the pre-staple archive."
print "Publication is a separate, explicit step."
