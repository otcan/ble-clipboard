# BLE Clipboard Protocol v2

The BLE and USB links have different roles: Bluetooth carries control/text from
the Mac; USB emits keyboard reports to a separate target. No BLE HID service is
published, and the BLE connection is not intentionally dropped to type.

## GATT

| Purpose | UUID | Behavior |
| --- | --- | --- |
| Service | `A6F1D9C0-7B21-4C9A-8E52-3D7710AA0001` | Advertised primary service |
| TX | `A6F1D9C0-7B21-4C9A-8E52-3D7710AA0002` | Read and notify |
| RX | `A6F1D9C0-7B21-4C9A-8E52-3D7710AA0003` | Authenticated writes |

The Mac scans by service UUID, discovers the characteristics, subscribes to TX,
then sends HELLO. Authentication uses bonded numeric-comparison Bluetooth
pairing. A matching HELLO is compatibility negotiation, not an independent secret.

## Frames

```text
offset  size  value
0       1     protocol version = 2
1       1     command/response ID
2       2     payload length, unsigned little-endian
4       N     payload bytes
```

GATT write chunks are at most 128 bytes and no larger than the negotiated
write-with-response limit. The Mac waits for each write callback before writing
the next chunk. Complete frames can span multiple writes.

| ID | Direction | Payload |
| --- | --- | --- |
| `0x01` HELLO | Mac -> Flipper | ASCII `BTPASTE-MAC/2` |
| `0x02` TYPE | Mac -> Flipper | One layout byte, then 1-3071 text bytes |
| `0x03` Reserved | Mac -> Flipper | Rejected: clipboard shortcut is not USB text |
| `0x04` CANCEL | Mac -> Flipper | Empty |
| `0x81` READY | Flipper -> Mac | Device name |
| `0x82` ACCEPTED | Flipper -> Mac | ASCII `type` |
| `0x83` DONE | Flipper -> Mac | Result text, including `cancelled` |
| `0xFF` ERROR | Flipper -> Mac | Error message |

Layout `0` is US. Layout `1` is Turkish Q and requires the SDK's `tr-TR.kl` asset.
TYPE's total payload limit is 3072 bytes including its layout byte. The Flipper
receive buffer is 4096 bytes. Response payloads are at most 124 bytes.

Only printable ASCII, Tab, LF, and CR are accepted. CRLF becomes one Enter. Text
is typed as individual HID press/release pairs after an initial 900 ms delay.

## Delivery Semantics

The Mac permits one transfer at a time, has connection/handshake timeouts, and
does not replay text on reconnect. READY is required before sending. ACCEPTED
means the Flipper validated and queued the command. DONE confirms HID submission,
not application-level receipt. A disconnect or cancellation can leave partial
text on the target; do not blindly resend.

No screen capture, file system, firmware update, or arbitrary script execution
command is exposed by this service.
