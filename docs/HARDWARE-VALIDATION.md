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

## Follow-up - 2026-11-02

- User approved macOS Bluetooth access and pairing on both devices.
- Native Mac app established the BLE link, but did not complete TTF1 setup.
- An independent Bleak probe connected, enumerated the expected RX/TX
  characteristics and enabled TX indications. No text frame or execute command
  was sent by that probe.
- User restarted Ducker Bluetooth with Hold Down, preserving bonds.
- After that restart, the handshake write was acknowledged but no `READY`
  response arrived before the probe timeout.
- Read-only diagnostics reported RX buffer capacity 1,024, consistent with the
  firmware RPC receiver rather than Ducker's configured buffer. The RPC status
  characteristic's first byte was active. This suggests a profile ownership
  conflict; it does not by itself establish the only failure cause.
- A small isolated-profile overlay was built for API 88.2. Host sanitizer tests
  verify distinct outer profile identity, original GAP configuration forwarding,
  failure cleanup and 100 repeated start/stop cycles.
- Compatibility FAP SHA-256:
  `7ac4f8449e47fe21c3fcdd767db09f6520df9179fab2eb587d69a4dc581aeac1`.
- Compatibility installation and hardware verification are pending the user
  exiting Ducker so USB serial becomes available. No device firmware or pairing
  key storage was changed by this overlay build.

The old source/app and initial pinned Ducker FAP remain available. No physical
typing pass or completed release gate is claimed at this checkpoint.

## Compatibility installation and handshake

- The owner exited Ducker, restoring USB serial access.
- Installed the compatibility app separately at
  `/ext/apps/GPIO/bt_paste_ducker_compat.fap`, displayed as **BT Paste Ducker**.
  The initial transfer was interrupted after overlapping CLI clients; both
  clients were stopped, the CLI recovered, and the transfer was redone in one
  exclusive serial session. No incomplete file was launched.
- Full USB read-back matched the local build's MD5 and SHA-256. SHA-256 remains
  `7ac4f8449e47fe21c3fcdd767db09f6520df9179fab2eb587d69a4dc581aeac1`.
- The independent BLE probe reported RPC inactive, receive buffer 486 bytes,
  `READY:1:65536` and `LAYOUT:QWERTY US`. It sent no typing payload or execute
  command. This verifies the profile-isolation fix for the observed handshake
  failure on this device/firmware.
- The native Mac preview then completed its own handshake and displayed
  **Ducker connected**. Its live picker showed all 28 layouts; Turkish Q was
  selected to match the test Mac.
- A 17-byte harmless sample was reviewed, but before the controlled run was
  started the preview's draft changed and it reported completion for different
  content. The dedicated capture file still contained zero input changes.
  No unexpected content was copied into this report.
- Controlled typing tests were paused pending exclusive control of the preview
  and capture windows. UI completion alone is not proof of target receipt.

**Passed:** install/read-back, independent TTF1 handshake, native TTF1 handshake.
**Not yet verified:** controlled USB delivery, literal brackets/whitespace,
macro parameters, cancellation, large transfers and interruption recovery.

## Controlled USB smoke test

- The owner granted exclusive use of the preview and dedicated capture windows.
- Reviewed and explicitly ran the 28-byte literal `BT Paste controlled test 123`
  using Turkish Q, with the preview hidden before output.
- The native capture recorded exactly those 28 bytes and 28 text changes. This
  verifies target delivery and focus restoration for this sample, not every
  layout or macro type.
- The Mac app subsequently timed out waiting for completion and disconnected.
  Therefore the complete run lifecycle did not pass, despite correct delivery.
- A follow-up build accepts completion after verified execution was requested
  even when the intermediate `SENDING` status is missing. The compatibility
  overlay also retries only rejected status indications, at most 32 attempts
  with 10 ms gaps; it never retries a received job or HID action.
- All 28 Swift tests and host sanitizer checks pass, including the missing
  intermediate-status and bounded status-retry cases. The updated firmware
  compiles for API 88.2. Installation and a repeated live run are pending.

## Status-reliability build installation

- The owner exited Ducker. The previous compatibility FAP was backed up and
  checked against the device checksum before replacement.
- Installed status-retry FAP SHA-256:
  `312d48253ee572be543cf447608d56a958c6b1c8691c86e166b64c0a23b45aa4`.
  Full USB read-back matched the build and device checksum.
- The native preview reconnected and completed TTF1 setup without a bond reset.
- An explicitly reviewed 28-byte sample produced native control messages
  `RECV`, `SENDING`, then `OK`. The preview displayed **USB output complete**
  and remained connected instead of reaching the prior watchdog timeout.
- The target capture remained empty on this attempt. Additional instrumentation
  showed the helper's editor selected while its application and window were
  inactive. Therefore this attempt verifies completion reporting, not target
  delivery; no complete end-to-end pass is inferred.
- The non-shipping helper now records its own active/key/focus state and has
  explicit activation in its Focus buttons. Automated activation still did not
  establish a verified active target. Further output is paused until the owner
  manually focuses the dedicated capture editor.

## Controlled delivery after manual focus

The owner focused the capture editor. Its persisted application-active,
key-window and editor-focus indicators were true before subsequent text runs.
All samples below were explicitly reviewed and executed, using Turkish Q on
the same official 1.5.1/API 88.2 device. Only the dedicated capture app received
test input; no system clipboard contents were used as payloads.

| Check | Observed result |
| --- | --- |
| 28-byte literal smoke sample | Exact match, 28 input changes; `RECV`, `SENDING`, `OK`; remained connected |
| Literal command-looking brackets | `[ENTER]`, `[WIN+r]`, `[]` and `{{clipboard}}` appeared as text, not commands/templates |
| Tab and LF in plain text | Present in the native capture |
| Full printable ASCII | Failed exact comparison; Turkish-Q punctuation/dead-key mismatch described below |
| JSON import through native file picker | Benign two-macro fixture imported into the preview library |
| Parameterized field navigation | First field exactly `Ada`, second exactly `Lovelace`; no text in the large editor |
| Stop during 30-second delay | Captured `before`; Stop disconnected; after the original delay elapsed, still six changes and no `AFTER` |
| Bonded reconnect after Stop | Native handshake succeeded; capture unchanged, no replayed output |
| 4,160-byte literal / SD-backed send | Exactly 4,160 bytes and 4,160 input changes; `OK` received; remained connected |

The large sample was `0123456789abcdef` repeated 260 times. Its receive
acknowledgement arrived at 12:27:21 UTC and completion at 12:28:57 UTC. A UI status
read timed out during continuous typing; no focus-changing recovery was attempted.
The final persisted native capture matched exactly and remained active/key/focused.

Local, ignored capture artifacts are under `Store/dist/hardware`, including
`status-retry-smoke-capture.json`, `ascii-layout-capture.json`,
`two-fields-capture.json`, `cancel-delay-capture.json`, `reconnect-capture.json`
and `large-transfer-capture.json`. They contain only the benign test samples.

### Open layout finding

The stock `tr-TR.kl` asset did not produce all printable ASCII correctly with
this Mac's Turkish QWERTY PC input source. Double quote, less-than, vertical bar
and grave accent differed; the grave accent combined with the following letter
as a dead key. Correct plain letters and brackets do not certify the whole
layout. Resolve or explicitly limit this combination before release, and test
other targets/layouts separately. No system input-source setting was changed.

The current preview is connected and idle with a short benign draft. No run is
queued. USB/cable loss, sleep/power-cycle, first-pairing rejection, other OSes,
other layouts, near-maximum payloads and other cancellation stages remain open.
