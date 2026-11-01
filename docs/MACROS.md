# Macros and Ducker

This branch adds a separate Mac Store target using DuckerTheFlipper. The original
`BluetoothClipboard/` app, SwiftPM/direct-download entry point and v2 codec stay
as the working 0.1.x baseline. Only the `MACROS_STORE` Xcode target selects the new
macro UI and Ducker backend. It does not connect to the legacy service. Do not
overwrite the working Flipper app to try the UI.

## Build and use

```sh
git submodule update --init --recursive
cd BLEClipboardMac
swift test
cd ..
sh scripts/check_ducker.sh
xcodegen generate --spec Store/project.yml
```

Open the generated Xcode project, select the Store scheme and build Debug. Debug
uses a separate `.MacrosPreview` bundle identifier. See `Store/README.md` for an
ad-hoc signed local build. Bluetooth is not initialized until Connect is pressed.

When the device is available for integration testing, install the pinned Ducker
build for its firmware, open DuckerTheFlipper, press Connect in the Mac app, and
choose the correct Flipper from Devices. Approve any Bluetooth pairing prompt on
both devices. The BLE pairing is handled by the system/Flipper serial profile;
the `TTF?` exchange checks protocol compatibility, not a separate password.
No new authentication or successful hardware pairing is claimed by this branch.

Use a plain text editor on a USB-connected target you own. Match the target OS
and keyboard layout, review the expanded output, confirm focus, and Run on USB.
If the same Mac is also the USB target, focus its intended input field before
opening the run review and enable Hide this app before output. macOS normally
returns focus to the previously active app; verify that behavior with harmless
text first. There is no global hotkey or cross-app Accessibility automation.

## Library

Five first-run macros: Type Clipboard, Saved Snippet, Timestamp, Replace Field,
and Fill Two Fields. The last one tabs between two fields and does not submit.
Macros support literal text, templates, key combinations and bounded delays.
Templates recognize `{{clipboard}}`, `{{timestamp}}` (ISO 8601 UTC), and named run
parameters. Replacement values are not recursively evaluated. Literal opening
brackets are escaped for Ducker; `[ENTER]` in clipboard text remains text.

`PRIMARY` maps to Command (`WIN`) on macOS and Ctrl on Windows/Linux. Letters in
key combinations are normalized to lowercase so `[CTRL+a]` does not add Shift.
Use an explicit Shift modifier when required. Newlines and tabs are real key
presses, not a clipboard API, and can submit forms or execute shell input.

Definitions live in `Application Support/BLE Clipboard/Macros/library.json`
inside the Store app's sandbox. The Mac is the source of truth. Saves are atomic,
with one validated `.backup` copy. Recovery never silently overwrites a corrupt
library. JSON export includes definitions, not run history; import copies entries
under new macro IDs and never executes them. Imports are bounded to 2 MB / 1,000
macros and reject unsupported versions, malformed steps, and unknown tokens.

Run arguments, clipboard snapshots, compiled scripts and delivery history are
not intentionally saved by the Mac. Literal text explicitly saved in a macro
is saved in the library and backup, including any secrets the user puts there.
Exports are ordinary unencrypted JSON. Files may be included in system backups.

Ducker itself keeps a RAM history for small payloads and uses an SD temporary
file for payloads over 4 KB. Do not treat the Flipper/SD card as secure storage;
deletion does not guarantee forensic erasure. This is not a password vault.

## Transfer contract

Pinned Ducker commit: `9d706967f7006702c9db3368235e6b6495176a46`.
GATT serial service `8FE5B3D5-2E7F-4A98-2A48-7ACC60FE0000`; Mac writes RX
`19ED82AE-ED21-4C9D-4145-228E62FE0000` and subscribes to TX
`19ED82AE-ED21-4C9D-4145-228E61FE0000`.

1. `TTF?` must receive `READY:1:<capacity>` (at most 65,536 bytes).
2. `TTFLAYOUT <layout>` must receive the matching `LAYOUT:<display-name>`.
3. `TTF1 <byte-count> <crc32>` and ASCII body are sent in 20-byte writes with
   response and a 50 ms pacing gap. Line endings are normalized to LF.
4. Only `RECV` permits sending `TTFEXEC`. No transfer is replayed on reconnect.
5. `WAIT_USB`, `SENDING`, `PROGRESS`, and `OK` drive the run state.

US is built in. Turkish Q requests `tr-TR.kl` and expects `LAYOUT:tr-TR`;
the file must already exist at `/ext/badusb/assets/layouts/tr-TR.kl`.
Text is ASCII only; arbitrary Unicode is rejected. At most 128 steps, 32
parameters, 30 seconds per explicit delay and 120 seconds total explicit delay.

The pinned backend has no remote cancellation command. Stop closes BLE
immediately, triggering its disconnect cancellation path. Reconnect manually.
Firmware variants may opt into `TTFCANCEL` only by advertising `CAPS:CANCEL`;
that extension is not included in this pinned backend. Ordinary successful runs
stay connected. A 45-second inactivity watchdog closes the connection; write
callbacks and status/progress renew it. No completion means uncertain delivery,
not permission to retry automatically. Cancellation cannot undo existing input.

## Verification boundary

Swift tests exercise validation, persistence/recovery and the transfer state
machine. Host C tests compile the pinned production HID engine with fake USB,
including bracket escaping and modifier handling. The pinned firmware builds
against official 1.5.1 / API 88.2. These do not prove actual BLE/USB compatibility,
numeric-comparison prompts, keyboard layout correctness or recovery on hardware.
Real-device release gates are tracked separately; this branch is pre-beta.
