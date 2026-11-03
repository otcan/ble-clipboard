#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
MODE=${1:---unsigned}
case "$MODE" in --unsigned|--signed) ;; *) printf '%s\n' 'Usage: sh scripts/archive_store.sh [--unsigned|--signed]' >&2; exit 2 ;; esac
if [ "$MODE" = --signed ]; then
    : "${DEVELOPMENT_TEAM:?Set the owner-confirmed Store team ID}"
    : "${STORE_SIGNING_IDENTITY:?Set the Mac App Store distribution certificate name}"
    : "${STORE_PROFILE:?Set the matching Store provisioning profile specifier}"
    case "$STORE_SIGNING_IDENTITY" in
        'Apple Distribution:'*|'3rd Party Mac Developer Application:'*) ;;
        *) printf '%s\n' 'Stop: use a Store distribution identity, not Apple Development or Developer ID.' >&2; exit 2 ;;
    esac
    [ "${STORE_RIGHTS_REVIEWED:-NO}" = YES ] || { printf '%s\n' 'Stop: licensing/rights review is not confirmed.' >&2; exit 2; }
    [ "${STORE_HARDWARE_TESTED:-NO}" = YES ] || { printf '%s\n' 'Stop: physical integration tests are not confirmed.' >&2; exit 2; }
fi
command -v xcodegen >/dev/null
xcodegen generate --spec Store/project.yml
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ARCHIVE="$ROOT/Store/Archives/BLEClipboard-$STAMP.xcarchive"
if [ "$MODE" = --signed ]; then
    xcodebuild -quiet -project Store/BLEClipboardStore.xcodeproj -scheme BLEClipboardStore \
        -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" archive DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$STORE_SIGNING_IDENTITY" \
        PROVISIONING_PROFILE_SPECIFIER="$STORE_PROFILE" \
        CURRENT_PROJECT_VERSION="${STORE_BUILD_NUMBER:-1}"
else
    xcodebuild -quiet -project Store/BLEClipboardStore.xcodeproj -scheme BLEClipboardStore \
        -configuration Release -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" archive CODE_SIGNING_ALLOWED=NO
fi
APP="$ARCHIVE/Products/Applications/BLE Clipboard.app"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
[ -n "$(plutil -extract NSBluetoothAlwaysUsageDescription raw "$APP/Contents/Info.plist")" ]
[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = com.oguzcanunver.BLEClipboardMac ]
[ "$(plutil -extract LSApplicationCategoryType raw "$APP/Contents/Info.plist")" = public.app-category.utilities ]
[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$(cat "$ROOT/VERSION")" ]
[ "$(plutil -extract CFBundleIconFile raw "$APP/Contents/Info.plist")" = AppIcon ]
[ -f "$APP/Contents/Resources/AppIcon.icns" ]
[ -f "$APP/Contents/Resources/LICENSE" ]
[ -f "$APP/Contents/Resources/NOTICE" ]
lipo "$APP/Contents/MacOS/BLE Clipboard" -verify_arch arm64 x86_64
if [ "$MODE" = --signed ]; then
    codesign --verify --deep --strict "$APP"
    printf '%s\n' 'Signed archive created. Export/validation/upload remain separate; this script does not submit.'
else
    printf '%s\n' 'Unsigned archive validated. This is NOT a Store-uploadable package.'
fi
printf 'Archive: %s\n' "$ARCHIVE"
