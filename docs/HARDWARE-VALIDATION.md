# Live hardware validation - 2026-11-01

This records observed results only. It is not a completed release certification.

## Setup

- Flipper Zero, official firmware 1.5.1, API 88.2 (read over USB CLI).
- Mac input source: Turkish QWERTY PC; match the Flipper output layout to it.
- Installed pinned Ducker at `/ext/apps/GPIO/bt_paste_ducker.fap`, leaving the
  existing BLE Clipboard app untouched. No firmware update or bond reset.
- Installed FAP read back over USB and SHA-256 matched the build:
  `1fbdb05cc1d118e96beeff857e55a6a0ebe354a49ff4b979fea0da44285a999e`.
- All 28 layout assets were present on the Flipper SD card; the Mac catalog now
  offers them. This does not claim physical typing verification of every layout.
- Capture helper instrumentation self-check passed; helper cleared afterward.

## Results

| Check | Observed result |
| --- | --- |
| Flipper USB CLI | Passed after user exited the legacy app with Back |
| Separate Ducker install/read-back | Passed |
| Launch | USB switched to HID after loader request; not proof of BLE handshake |
| Native Mac discovery | Test Flipper discovered |
| Native serial setup | First attempt reached GATT write and failed; diagnosis pending |
| Diagnostic rebuild | CoreBluetooth authorization request pending macOS approval; system prompt requires user action |
| Handshake `READY` | Not verified yet |
| USB text/macro output | Not tested yet |
| Cancel, reconnect, cable loss, sleep | Not tested yet |
| 28-layout serialization and acknowledgement unit tests | Passed |

No test payload has been executed by the new Mac app at this checkpoint.
Do not mark physical delivery, first pairing or interruption cases complete.

The Mac app now surfaces the GATT error domain/code and allows cancelling a
connection attempt. This is diagnostic work, not a bypass of authentication.
The dedicated capture app supports ordinary Edit commands and has no global
keyboard hook. No production document was used as the USB target.
