# Security

BLE Clipboard turns text into USB keyboard events. Use it only on devices you
own or are authorized to operate. Newlines and tabs have normal key behavior.

## Trust Model

- Compare Bluetooth pairing codes on both devices. Do not accept a mismatch.
- Pair only with a computer you trust. The protocol's HELLO is not a password.
- Other processes on a paired computer may access the BLE peripheral.
- The target must trust the attached USB keyboard. It does not authenticate this app.
- USB HID submission does not guarantee which target application received text.
- The application does not offer arbitrary script execution or firmware/file access.
- Clipboard text is held in memory, not intentionally stored. Pairing keys remain
  on the Flipper SD card and preferences retain the Mac's peripheral identifier.
- Early release artifacts are ad-hoc signed and not notarized. Inspect checksums
  and source; do not disable operating-system security protections.

## Reporting

For non-sensitive bugs, open an issue without passwords, pairing keys, or real
clipboard contents. For vulnerabilities, use the repository's GitHub security
advisory reporting when enabled. Do not post exploitable details or private
clipboard data in a public issue.
