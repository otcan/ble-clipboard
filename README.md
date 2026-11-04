<p align="center">
  <img src="BLEClipboardMac/Resources/AppIcon.png" width="100" alt="BLE Clipboard icon">
</p>

<h1 align="center">BLE Clipboard</h1>

<p align="center">Your Mac's clipboard and macros, delivered through Flipper Zero.</p>

<p align="center">
  <a href="#install-the-matching-pair">Download &amp; Install</a> &middot;
  <a href="#use">Quick Start</a> &middot;
  <a href="docs/MACROS.md">Macro Guide</a> &middot;
  <a href="CHANGELOG.md">Changelog</a>
</p>

Review text or create a macro on your Mac, then send it over Bluetooth LE to
Flipper Zero. Connected by USB, the Flipper acts as a keyboard and mouse on the
target device. No companion app is needed on the target.

```text
Mac app -- Bluetooth LE --> Flipper Zero -- USB keyboard/mouse --> Target
```

Free and open source under GPL-3.0-only. The current release is
[0.5.3](https://github.com/otcan/ble-clipboard/releases/tag/v0.5.3).

## Features

| Feature | What you can do |
| --- | --- |
| Quick Paste | Load clipboard text or import a text file, review it, then send it as USB keystrokes. |
| Macros | Combine text, templates, parameters, keyboard shortcuts, delays, mouse movement and timed repeats. Import and export your library as JSON. |
| Saved jobs | Keep up to 20 clipboard or macro snapshots on the Flipper's SD card and run them without the Mac. |
| Standalone runs | Continue selected jobs without the Mac, with a timer and physical Stop. Timed repeats support up to 24 hours. |
| Target layouts | Choose from 28 keyboard layouts for both Quick Paste and macros. See [text support and layout requirements](#layouts-and-text). |

## Install the Matching Pair

Install **both apps from the same release**. The Mac app creates and sends jobs;
the Flipper app runs them over USB.

| App | Requirements | Download 0.5.3 |
| --- | --- | --- |
| Mac | macOS 14 Sonoma or later; Apple Silicon or Intel | [Universal Mac ZIP](https://github.com/otcan/ble-clipboard/releases/download/v0.5.3/BLE-Clipboard-0.5.3-universal.zip) |
| Flipper Zero | Packaged FAP targets official firmware 1.5.1 / API 88.2 | [ble_clipboard.fap](https://github.com/otcan/ble-clipboard/releases/download/v0.5.3/ble_clipboard.fap) |

The published Mac app is **Developer ID signed, Apple-notarized and ticket-stapled**.
Verify downloads against [SHA256SUMS.txt](https://github.com/otcan/ble-clipboard/releases/download/v0.5.3/SHA256SUMS.txt).
No Gatekeeper bypass is needed.

You will also need a USB data cable. An SD card is required for saved jobs,
programs larger than 4 KiB and most keyboard layout files.

### Mac

Install through the [Homebrew tap](https://github.com/otcan/homebrew-ble-clipboard):

```sh
brew tap otcan/ble-clipboard
brew install --cask otcan/ble-clipboard/ble-clipboard
```

Or download the Mac ZIP above, verify its checksum, unzip it and move
**BLE Clipboard.app** to Applications. Quit an older copy before replacing it.

**Homebrew installs only the Mac app.** Install the Flipper companion separately.

### Flipper Zero

1. Stop any running job and exit the Flipper app to its home screen so USB is
   available to qFlipper.
2. Connect the Flipper to your Mac by USB. Using qFlipper, copy the matching FAP
   to `/ext/apps/Bluetooth/ble_clipboard.fap`. Preserve an older copy first if needed.
3. Open **Apps > Bluetooth > BLE Clipboard** on the Flipper.

The [Flipper Apps Catalog submission](https://github.com/flipperdevices/flipper-application-catalog/pull/1379)
is awaiting maintainer review. Use the FAP download above until it is accepted.

### Updating

Quit the Mac app before upgrading:

```sh
brew update
brew upgrade --cask otcan/ble-clipboard/ble-clipboard
```

Then exit the Flipper app and replace its FAP with the matching version.
Version 0.5.3 fixes SD initialization for saving snapshots and programs larger
than 4 KiB. No SD formatting, saved-job migration or pairing-key deletion is needed.
See the [changelog](CHANGELOG.md) for earlier releases and compatibility notes.

## Use

1. Open both apps. On the Mac, choose **Connect**, select your Flipper and allow
   Bluetooth access. Compare and approve the matching pairing codes on both devices.
2. Connect the Flipper by USB to a device you own or have permission to operate.
   The USB target can be the source Mac or another computer.
3. Choose **Quick Paste** or a macro, then match the target OS and keyboard layout.
4. Review the expanded text and actions. Focus a disposable plain text document
   on the target, confirm the target and choose **Run on USB**.

If the source Mac is also the target, hide the Mac app before output and check
the receiving document's focus. Focus restoration is not guaranteed.

**To stop:** use Stop on the Mac, or press **Left or Back** on the Flipper during
a job. Stop releases Flipper-held keys and mouse buttons but cannot undo input
already sent. Tabs and newlines are real keys: start with a text document, not
a terminal, password field or form that submits on Enter.

## Standalone Jobs and Mouse Jiggle

**Send to Flipper** saves a reviewed clipboard or macro snapshot without running
it. Clipboard text, timestamps and parameter values are fixed at send time.
The SD library holds up to 20 entries. Sending the same macro again replaces its
snapshot; separate Quick Paste reviews create separate entries.

On the Flipper, **Up/Down** selects an entry, **OK** opens it and **Run** needs a
second confirmation with a three-second focus allowance. **Right** opens Delete
confirmation. Saved entries survive restart, but never run automatically.

For a live job, enable **Continue on Flipper if this Mac disconnects** in run
review to keep it running without the Mac. Normal jobs stop on Bluetooth loss.
Standalone jobs show elapsed/remaining time, can be stopped on the Flipper and
end permanently on USB loss, app exit or power loss. Reconnecting the Mac lets
you view and stop the active job; it does not restart it.

**Move Mouse** and **Repeat** support fixed values or ranges. The Mouse Jiggle
preset creates an eight-hour repeat with X/Y ranges of -2...2 HID units and
45...95-second intervals; you can edit those values before running it.
Movement releases Flipper-held mouse buttons first, but cannot override another
mouse's held button or an OS drag-lock setting. Movement may drift and is not
guaranteed invisible, undetectable or to prevent an application's idle policy.
See the [macro guide](docs/MACROS.md) for step limits, templates and repeat behavior.

## Layouts and Text

The layout must match the **USB target's input source**, not necessarily the Mac's.
Most layouts support printable ASCII, Tab and line breaks. Native Turkish
letters are experimental with Turkish Q; arbitrary Unicode, other native
alphabets and IME input are not supported.

US and macOS Turkish Q are built in. The Turkish map targets Apple's
**Turkish QWERTY PC**, not Turkish Q Legacy. Most other choices need the matching
official `.kl` file under `/ext/badusb/assets/layouts/`. Missing or unmapped
layout assets reject the job before it runs.

<details>
<summary>All 28 target layout choices</summary>

US/UK, Turkish Q, Bosnian, Czech, Danish, German/Swiss German, Dvorak,
Spanish/Latin American, French/Belgian/Canadian/Swiss/Mac French, Croatian,
Hungarian, Italian/Mac Italian, Japanese, Norwegian, Dutch, Portuguese/Brazilian,
Slovenian, Slovak and Swedish.

</details>

## Privacy

Clipboard access is explicit. There is no cloud account, analytics service,
clipboard watcher, global keyboard hook or target-side agent. Bluetooth pairing
protects transfers, but does not encrypt files saved on either device.

Mac definitions, backups, JSON exports and saved SD snapshots are **plaintext**.
Jobs larger than 4 KiB also use a temporary SD file, cleaned up on completion,
Stop, exit or the next startup. Deleting a file is not secure erasure.
Logs omit text and parameter contents. See [SECURITY.md](SECURITY.md) for security
reporting and [protocol details](docs/PROTOCOL.md) for the transport model.

## Info and Companion Downloads

**Info & Companions** on the Mac shows both app versions and links to their
matching release. On the idle Flipper screen, press **Right** for Info, then
**OK** for its download QR code.

Opening or refreshing the Mac Info panel checks that version's public GitHub
release. Downloads are enabled only when the matching app assets and checksum
file are available. There is no automatic download, installation or fallback
to an older version. Older companions may report their app version as Unknown.

## Status and Feedback

This is an **early 0.x release**. Automated Swift and C checks cover macro
compilation, protocol handling, layouts, storage and cancellation, but are not
hardware certification. Fresh physical save/run, wider focus/layout and
multi-hour target checks remain open; see the [validation record](docs/HARDWARE-VALIDATION.md).

Found a bug? [Open an issue](https://github.com/otcan/ble-clipboard/issues) with
your Mac version, Flipper firmware, target OS/layout and non-sensitive steps
to reproduce. Do not include real clipboard data, secrets or pairing keys.

## Build

For development, install Xcode/Swift and uFBT with the matching official SDK:

```sh
swift test --package-path BLEClipboardMac
sh scripts/check_clipboard.sh
UFBT=ufbt sh scripts/build_flipper.sh
BLEClipboardMac/build_app.sh --universal
```

Source builds are ad-hoc signed by default; they are not the notarized release
download. Building does not install either app or start keyboard/mouse output.
See [development and release](docs/DEVELOPMENT.md) for prerequisites, packaging
and signing, and [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## Documentation

[Macro guide](docs/MACROS.md) &middot; [Protocol](docs/PROTOCOL.md) &middot;
[Validation](docs/HARDWARE-VALIDATION.md) &middot;
[Development](docs/DEVELOPMENT.md) &middot;
[Store preparation](Store/README.md) &middot; [Changelog](CHANGELOG.md)

## License

[GPL-3.0-only](LICENSE). Not affiliated with Flipper Devices, Apple or Homebrew.
See [NOTICE](NOTICE) for notices and [artwork provenance](docs/ARTWORK.md).
