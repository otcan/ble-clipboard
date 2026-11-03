# Development and Release

Version 0.5.2 is an independent Mac/Flipper pair. There is no vendor submodule or
third-party typing backend. Keep the running app and connected device untouched
unless installation or live testing is separately requested.

## Source

| Path | Responsibility |
| --- | --- |
| `BLEClipboardMac/Sources` | Mac UI, library, compiler, binary codec and BLE client |
| `BluetoothClipboard/clipboard_app.c` | Flipper SDK, BLE/USB, GUI and RAM/SD adapters |
| `BluetoothClipboard/clipboard_hid.h` | Button-up movement and keyboard/mouse cleanup adapter |
| `BLEClipboardMac/Sources/BLEClipboardMac/Companion*` | Info UI, pinned release metadata and availability checks |
| `BluetoothClipboard/transfer_protocol.*` | Independent framed upload/job state machine |
| `BluetoothClipboard/macro_engine.*` | Typed-program validation and nonblocking execution |
| `scripts/tests` | Independent fake-USB, lifecycle, sanitizer and fixture checks |
| `Store/` | Same Mac features with App Sandbox and separate Store preparation gates |

## Build and Check

macOS 14+, Swift 5.9+/Xcode and uFBT 0.2.6 configured for official firmware 1.5.1 /
API 88.2 are required. No submodule initialization is necessary.

```sh
swift test --package-path BLEClipboardMac
sh scripts/check_clipboard.sh
UFBT=ufbt sh scripts/build_flipper.sh
BLEClipboardMac/build_app.sh --universal
```

The host checks run the actual C engine/server with AddressSanitizer and UBSan.
The Swift tests emit complete wire fixtures; C consumes them and captures fake
HID reports, including a 64 KiB job, literals, Turkish letters and structured
macros. On macOS, Carbon checks the captured Turkish map against installed
keyboard translations. No USB device is opened, no input source is changed and
no events are injected. These checks are not hardware certification.

The build outputs are `BLEClipboardMac/dist/BLE Clipboard.app` and
`BluetoothClipboard/dist/ble_clipboard.fap`. The Flipper build also creates
corresponding source and source fingerprints. It never calls `ufbt launch`.
Installation requires normal USB serial mode after the owner exits the old app.

## Package 0.5.2

```sh
scripts/package_release.sh 0.5.2
```

The version must match `VERSION`; the script rejects rebuilding older versions.
It checks the built FAP's source fingerprints, builds a universal Mac app, uses
`ditto` for the ZIP, includes both corresponding source archives, README, NOTICE,
LICENSE, fingerprints and checksums under `dist/v0.5.2`. Source archives snapshot
the allowlisted current working tree, including local development changes,
while excluding build products, private keys and local account configuration.

The default signature is ad-hoc. It verifies integrity, not Developer ID identity
or notarization. No packaging command publishes, submits to Apple, installs the
apps or changes the user's running processes/device.

For a later authorized signed release, configure Developer ID locally, use
`scripts/notarize_release.sh 0.5.2` deliberately, then staple/verify and generate
the Homebrew cask from the final ZIP. Never rerun a rebuild/resubmit script to
resume a pending notarization. Never export signing keys or put credentials in
CI, shell arguments, source or chat. The old 0.1.1 submission/artifacts are not
part of the 0.5.2 release and must remain unchanged.

## Companion Metadata

After changing VERSION, run `swift scripts/generate_companion_assets.swift`.
This uses Core Image to generate the version headers, Swift build version and
the Flipper QR bitmap, then decodes the QR to verify the exact release URL.
The PNG/C array include a four-module quiet zone. Generated headers are included
in the FAP source archive, so a Flipper-only build does not require a QR library
or Swift at runtime. Local checks and Mac packaging reject stale generated files.

The Info panel's public GitHub request is explicit (panel open/refresh), ephemeral,
unauthenticated and version-pinned. Store builds need network-client entitlement
for this check; no other runtime HTTP service is introduced. Preview identities
ending in `.InfoPreview`, like `--ui-testing`, use a temporary library, no BLE and
an offline unpublished-release result. This does not certify the sandboxed target.

## Publish Later

Pass the hardware/release checklist first. Commit the actual tested source,
push and tag that revision. The workflow creates an ad-hoc draft, not an automatic
public release. Replace every draft artifact as one matching set if preparing a
locally signed/notarized release, including the FAP and both source archives.
Never overwrite assets of an already public immutable version.

Generate the cask with `scripts/generate_cask.py` from the final ZIP only after
the public URL/checksum match. Do not update the installed app or tap as part of
a development build. Store signing, licensing review, metadata, beta testing and
App Review remain a separate gated path in `Store/README.md`.
