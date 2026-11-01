# BLE Clipboard for macOS

Native macOS companion for the Flipper Zero **BLE Clipboard** application.
See the [project README](../README.md) for downloads, Homebrew installation,
screenshots, and the complete setup guide.

## Flow

Mac app -> authenticated Bluetooth LE -> Flipper -> USB keyboard -> target.

1. Open **Apps > Bluetooth > BLE Clipboard** on the Flipper.
2. Open `dist/BLE Clipboard.app` on the Mac. Allow Bluetooth access if requested.
3. Compare and approve the pairing code on the Mac and Flipper. The BLE name is
   **Paste**. The app only enables sending after the secure protocol handshake.
4. Connect the Flipper's USB cable to the target device and focus its text field.
5. Enter text in the Mac app, or click **Load Clipboard**. Select the target's
   active keyboard layout, then **Send to USB**.

The Bluetooth connection stays open. There are no script files, profile switching
between commands, or target-side software requirements. The Mac app hides after
acceptance to restore focus when the USB target happens to be this same Mac.
Text is only sent on an explicit click; the clipboard is not watched automatically.

## Limits and Safety

- Currently supports 1-3071 ASCII characters, plus tabs and line breaks. Unsupported
  characters are rejected before sending, not silently transliterated.
- US and Turkish Q target layouts are available. Turkish Q requires the firmware
  asset `/ext/badusb/assets/layouts/tr-TR.kl`.
- This types text; it does not transfer the target's OS clipboard or emit Command-V.
- Tabs and newlines are real Tab and Enter keystrokes. Start with a plain text
  editor, not a terminal or a form that submits on Enter.
- Cancel stops typing; Back on the Flipper exits and restores normal USB/Bluetooth.
  Disconnection stops pending typing. Requests are never automatically replayed.
- Bluetooth's authenticated numeric-comparison pairing protects the transport.
  The HELLO exchange checks protocol compatibility; it is not an independent
  app-level credential. Pair only with a computer you trust.
- Text is not written to disk by these apps. Saved settings contain only the target
  layout and the paired CoreBluetooth identifier. Diagnostic logs omit clipboard data.

## Troubleshooting

- The USB serial port disappears while this app runs because USB is a keyboard.
  Exit with Back before using qFlipper or uploading another build over USB.
- For **Pairing incomplete**, click Connect and approve the matching code on both
  devices. Do not disable encryption to work around a pairing failure.
- For **USB target not connected**, check the data-capable USB cable and target.
- A successful send means HID reports were sent, not that a specific target app
  received the intended text. Check the target before retrying a partial send.

## Development

Build with `./build_app.sh`. The resulting application is written to
`dist/BLE Clipboard.app`.

Run `swift test` for protocol framing and text-validation tests. Build the Flipper
app from `../BluetoothClipboard` using the workspace `.venv/bin/ufbt` (API 88.2).

Protocol v2: `[version=2, command, uint16LE payload length, payload]`.
HELLO `0x01` carries `BTPASTE-MAC/2`; TYPE `0x02` carries a layout byte (0=US,
1=Turkish Q) followed by text; CANCEL is `0x04`. Responses are READY `0x81`,
ACCEPTED `0x82`, DONE `0x83`, and ERROR `0xFF`. The Mac caps GATT writes at
128 bytes and waits for each write response. The Flipper caps text payloads
at 3072 bytes including the layout byte. Response payloads are at most 124 bytes.

Service: `A6F1D9C0-7B21-4C9A-8E52-3D7710AA0001`.
TX notifications: `A6F1D9C0-7B21-4C9A-8E52-3D7710AA0002`.
RX authenticated writes: `A6F1D9C0-7B21-4C9A-8E52-3D7710AA0003`.

Verified on 2026-11-01 with firmware 1.5.1 / API 88.2: both builds and eight unit
tests pass; the installed Flipper enumerates as a USB HID keyboard; the Mac
discovers the BLE service and completes the handshake with the Flipper. The user
confirmed that sending `test` successfully typed it into the USB-connected target.
Long transfers, cancellation during typing, and Turkish Q output have not yet
been verified end to end on hardware.
