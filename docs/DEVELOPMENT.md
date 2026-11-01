# Development

## Source Layout

| Path | Contents |
| --- | --- |
| `BLEClipboardMac/` | Swift package, native app, tests, bundle resources |
| `BluetoothClipboard/` | Flipper FAP, compact display, BLE service, USB typing |
| `scripts/` | Icon generation, universal packaging, cask generation |
| `packaging/homebrew/` | Cask template; the live cask is in the separate tap |
| `.github/workflows/` | CI and tag-triggered draft releases |

The original developer workspace holds other projects. Its `.gitignore` uses an
allowlist so those projects, credentials, keys, virtual environments, and SDK
checkouts cannot be accidentally staged by a normal `git add`.

## Mac

Requires macOS 14+, Xcode Command Line Tools, and Swift 5.9+.

```sh
cd BLEClipboardMac
swift test
./build_app.sh                 # current architecture
./build_app.sh --universal     # arm64 + x86_64
open "dist/BLE Clipboard.app"
```

The icon source is `Resources/AppIcon.png`. `scripts/build_icon.sh` makes the
ICNS sizes using macOS tools. The bundle keeps the same identifier across
versions so Bluetooth permission and preferences continue to work.

## Flipper

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install ufbt==0.2.6
ufbt update --branch 1.5.1
cd BluetoothClipboard
ufbt
ufbt launch
```

The release targets API 88.2, official firmware 1.5.1. For another firmware,
select its SDK and rebuild. Do not assume a FAP for one API works on another.
The output is `BluetoothClipboard/dist/ble_clipboard.fap`.

`ufbt launch` needs the Flipper's normal USB serial interface. While BLE
Clipboard runs, USB is HID-only. Exit with Back before attempting an upload.
The SD card must include the firmware's Turkish Q asset to use that layout.

## Hardware Checklist

Use a plain text editor on a target you control. Never use a shell for smoke tests.

- Compare the first pairing code on Mac and Flipper; reject mismatches.
- Confirm reconnection after relaunch without pairing again.
- Send a short ASCII sample and check the target.
- Test newlines, tabs, punctuation, and both target layouts.
- Reject non-ASCII and oversized input without typing partial replacement text.
- Test a 3071-byte payload, cancellation, and cable/BLE loss during typing.
- Exit on Flipper and confirm the normal serial/Bluetooth interfaces return.

Only the short ASCII path and automatic reconnection have been observed so far.
Do not describe the untested hardware cases as certified.

## Releases

1. Update `VERSION`, the bundle version, and `CHANGELOG.md`.
2. Run unit tests and build the pinned Flipper FAP.
3. Run `scripts/package_release.sh 0.1.0` from the repository root.
4. Review the source allowlist, artifacts, signatures, and SHA-256 checksums.
5. Commit, tag `v0.1.0`, and publish the reviewed assets on GitHub.
6. Generate the cask into the tap repository:

```sh
python3 scripts/generate_cask.py 0.1.0 \
  dist/v0.1.0/BLE-Clipboard-0.1.0-universal.zip \
  ../homebrew-ble-clipboard/Casks/ble-clipboard.rb
```

Commit and push the cask only after its URL and checksum match the public asset.
The release workflow intentionally creates a **draft**, not an automatic public
release, so hardware checks and signing can be reviewed first. Release packaging
uses `ditto` to preserve the macOS application bundle.

## Signing and Homebrew

The default build uses an ad-hoc signature. This verifies bundle integrity but
does not provide a Developer ID identity or Apple notarization. Apple Development
certificates cannot substitute for Developer ID distribution.

For a signed build, set `CODE_SIGN_IDENTITY` to an available Developer ID identity
before packaging. Submit the resulting artifact with your own Apple notarization
credentials, then staple and verify the ticket before distributing it. Never
commit signing keys, certificate passwords, or Apple credentials.

The first release uses a third-party Homebrew tap. It does not remove quarantine,
disable Gatekeeper, or claim admission to the official Homebrew cask repository.
See the [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) and
[signing audit policy](https://docs.brew.sh/rubydoc/Cask/Audit.html).
