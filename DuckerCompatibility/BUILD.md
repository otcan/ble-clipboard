# BT Paste Ducker compatibility build

Development build; live BLE handshakes are verified on official 1.5.1/API 88.2.
The status-retry build delivered exact 28-byte and 4,160-byte samples and reported
completion without disconnecting. Delay cancellation, parameterized field output
and bonded reconnect without replay also passed. Turkish-Q punctuation on the
test Mac and the broader release matrix remain open. Upstream remains pinned
and unmodified in Git.
The build script archives that source and applies this small overlay; the
resulting complete source is shipped alongside its FAP.

The official firmware's BT service automatically attaches RPC to profiles whose
`config` equals `ble_profile_serial`. The compatibility profile has a distinct
outer identity and delegates services/GAP to the stock serial profile. Ducker
receives the inner instance, retaining the same service UUIDs, authenticated
attributes, bonding keys, pairing method and TTF1 protocol. It does not erase
bonds, modify the firmware, disable authentication or add an execution command.

The overlay retries rejected outgoing status indications with a bounded 32-attempt
budget and 10 ms gaps. It does not replay payloads or HID actions. Host tests
verify immediate success, transient backpressure and permanent rejection.

The ownership assumptions in the proxy stop callback are pinned to SDK 1.5.1 /
API 88.2: stock serial_stop destroys GATT services, but does not free its profile
allocation. Review that implementation before using another SDK.

On the test device, this variant changed the observed receive buffer from
1,024 to 486 bytes and produced the missing TTF1 `READY` response. The native
Mac client then connected successfully. See `docs/HARDWARE-VALIDATION.md` in the
BT Paste repository for the detailed verification boundary.

From the repository: `sh scripts/build_ducker_compat.sh` (uFBT must be available).
From the complete generated compatibility source archive: extract it, then run
`ufbt` against official firmware SDK 1.5.1 / API 88.2. Output is
`dist/bt_paste_ducker_compat.fap`. Keep upstream's copyright and GPL notices.

Primary implementation references:

- https://github.com/flipperdevices/flipperzero-firmware/blob/1.5.1/applications/services/bt/bt_service/bt.c
- https://github.com/flipperdevices/flipperzero-firmware/blob/1.5.1/targets/f7/ble_glue/profiles/serial_profile.c
- https://github.com/flipperdevices/flipperzero-firmware/blob/1.5.1/targets/f7/furi_hal/furi_hal_bt.c
