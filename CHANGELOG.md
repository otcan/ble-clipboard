# Changelog

## 0.5.4

- Add the full Windows x64 companion as an unsigned beta: searchable macro
  library/editor, templates/parameters, shortcuts, Move Mouse/Repeat, import/export,
  atomic backups/recovery, reviewed runs and compiled SD snapshots. Mac-compatible
  schemas 1-3 preserve identifiers and migrate legacy mouse definitions.
- Add Fast, Slow (+80 ms), Variable (+80 +/- 30 ms) and bounded Custom typing
  on both desktops. Optional opcode 7 captures pacing in compiled snapshots;
  older Flipper companions reject non-Fast pacing before upload.
- Windows device selection, authenticated-pairing guidance, standalone timers,
  reconnect attachment without replay, and remote Stop. Bluetooth runs on an MTA
  worker rather than Tk's main thread.
- Windows x64 portable bundle and per-user installer generated from VERSION,
  with no administrator requirement or automatic launch. Libraries survive
  upgrades/reinstall/uninstall. Info checks exact-version companion assets.
- Shared Swift/Python compiler fixtures executed by the C engine; native Windows
  offline UI and installer CI gates. Physical BLE/USB/focus/layout/long-run tests
  remain explicitly unverified.
- Add Flipper's idle Left > Keyboard menu with all 28 layouts, target OS and
  explicit Save. Keyboard settings persist on SD across disconnects and restarts.
- Optional device keyboard override for local saved-job runs. Show the effective
  target/layout before Run, validate the entire program against it, and leave
  snapshot files unchanged. Original saved layouts remain the upgrade default.
- Sync keyboard settings in both directions with the Mac; Flipper wins on
  reconnect. Quick Paste and new macro defaults share the synced preference;
  existing Mac macro definitions retain their explicit target/layout.
- Optional protocol-4 capability, correlated settings replies and revision checks
  reject stale edits without retrying. Busy jobs reject changes; sync does not
  emit HID input, execute jobs or change a running job's keyboard.
- Atomic settings replacement/recovery; failed writes leave the previous setting
  active. No automatic English fallback when a selected layout is unavailable.
- Building/publishing does not replace installed apps. Physical disconnected/
  reconnected checks remain unverified and require separate owner approval.

## 0.5.3 - 2026-11-04

- Fix Flipper SD directory initialization: use the application-data root without
  a trailing slash, which the firmware filesystem rejects. This restores saved
  snapshots and temporary storage for transfers larger than 4 KiB.
- Reproduce the firmware path restriction in saved-library regression tests.
- Report Mac save failures as failed snapshots, not rejected USB runs; retain
  the save context before the transfer session resets.
- No snapshot-format change, slot-limit change or automatic app replacement.

## 0.5.2 - 2026-11-03

- First independent public release, combining the clipboard, macro, 28-layout,
  standalone, SD-library and ranged Move Mouse/Repeat work from local 0.3-0.5.1
  builds. Earlier public 0.1.0 artifacts remain unchanged.
- Info & Companions on the Mac toolbar and Help menu: actual app versions,
  compatibility, matching Mac/FAP downloads, checksums, source and support links.
- Anonymous, on-demand checks of the exact GitHub release; both downloads stay
  disabled for unpublished/incomplete releases or a failed check. No latest-version
  fallback, automatic installation or update of running apps.
- Flipper Info/Downloads screens with the full patch version and a version-pinned
  release QR bitmap generated and decoded with Core Image.
- Optional read-only protocol-4 version query: older clients still connect, older
  companions show Unknown, and querying metadata never starts or changes a job.
- Retained the 0.5.1 button-release guard and existing macro/snapshot formats.
  Installed apps are not replaced by building or publishing this release.
- Read-only Flipper --info launch path for qFlipper inspection/screenshots,
  returning before Bluetooth, HID or saved-library setup. Shared normal/Info-only
  views use a compact QR code button without footer overlap.

## 0.5.1 - Unreleased

- Move Mouse clears every Flipper mouse button before movement and refuses to
  move if the button-up report fails. The previous direct HAL call retained
  inherited button state, which could turn movement into a drag.
- Startup, key release, Stop, failure/completion and exit now clear both keyboard
  and mouse state. Cleanup attempts both reports even when one fails.
- Added sanitizer-enabled HID adapter checks for stale left/right/middle buttons,
  neutral reports, exact movement deltas and failure/disconnection behavior.
- Protocol, saved snapshots and macro definitions are unchanged; updating the
  Flipper binary applies the guard to existing saved mouse jobs too.
- Local development build; no live input regression test or public release yet.

## 0.5.0 - Unreleased

- Generic Move Mouse with fixed/ranged X/Y offsets and timed Repeat sequences;
  Mouse Jiggle is a preset rather than a selectable action.
- The preset defaults to eight hours, -2...2 HID units on each axis, and 45...95
  second cycle intervals, sampled on Flipper. No undetectability claim.
- Preserved timer, physical Stop, standalone execution and saved SD snapshots.
  Repeats never overlap, and deadlines release keys before advancing to the tail.
- Schema 1/2 remains readable; legacy mouse definitions migrate to generic steps,
  new documents use schema 3. Existing binary snapshots remain playable and unchanged.
- Capability checks prevent sending new actions to 0.4; cursor progress remains
  monotonic despite internal rewinds. Validation covers every repeated body.
- Tests cover sampled bounds, entropy failure, eight simulated hours, tick rollover,
  cancellation and deadline key release without hardware input.

## 0.4.0 - Unreleased

- Mouse Jiggle with duration/interval controls and up to 24 hours total. Small
  alternating movement, no clicks/keys/scrolling or target-side software.
  USB/input activity remains observable; no undetectability claim.
- Explicit standalone execution survives Mac quit/BLE loss; Left/Back stops it,
  and Flipper shows elapsed/remaining time. USB loss stops permanently.
- Save reviewed clipboard snapshots or expanded macros to a 20-entry SD library
  with metadata/body CRC, atomic replacement and recovery; no output on save.
- Flipper browser, confirmed local Run with focus allowance, and confirmed Delete;
  no automatic execution after startup, reconnect or USB reconnection.
- Protocol 4 reattaches remote Stop to active standalone jobs without replay.
  Normal jobs retain stop-on-disconnect behavior. Both apps need the update.
- JSON schema 1 stays readable; mouse-containing documents use schema 2.
- Host-clock hours/wraparound tests, offline Stop/failure/reconnect, and SD
  persistence/corruption/interrupted-replacement tests without hardware output.

Local development version only. Fresh physical BLE/USB/SD and multi-hour hardware
validation remain open. No firmware flash, public release or notarization.

## 0.3.0 - Unreleased

- Independent Mac and Flipper apps; removed the Ducker submodule, overlays,
  script grammar, transport and build/test dependencies.
- Native typed binary macro format: text cannot become a script or key record.
- Versioned custom authenticated BLE service, bounded 512-byte chunks,
  CRC-32, whole-program validation and explicit execution after verification.
- Up to 64 KiB per encoded macro; RAM for small jobs and temporary SD storage
  for larger jobs, with cleanup on completion, cancellation, loss or exit.
- Retained Quick Paste, text-file import, saved macros, parameters, templates,
  shortcuts, delays, review, JSON import/export and backup recovery.
- Retained the 28-layout catalog and experimental native Turkish letters;
  built-in macOS Turkish QWERTY PC mapping, without script extension tags.
- Remote Stop keeps Bluetooth connected; USB/BLE loss and sleep stop output,
  and old jobs are never replayed automatically.
- Cross-language Swift-to-C fixtures, sanitizer/fuzz checks and keyboard
  translation tests; fresh live hardware and Store acceptance remain open.

Both apps must be updated together. This is a local development version, not
a published or notarized release. Existing 0.1.x artifacts are unchanged.

## 0.2.0 - Superseded Unpublished Prototype

- One standard Mac app with Quick Paste and the existing saved-macro library,
  parameters, key combinations, delays, import/export and explicit run review.
- The same 28 target keyboard layouts in Quick Paste, macros and the retained
  legacy protocol interface; missing layout files fail before typing.
- Experimental Turkish Q letters: U+00C7/00E7, U+011E/011F, U+0130/0131,
  U+00D6/00F6, U+015E/015F and U+00DC/00FC, including decomposed input.
- Native letters require a matching updated Flipper app, not raw UTF-8 sent to
  an ASCII-only engine. Other native scripts and arbitrary Unicode remain unsupported.
- Direct-download packages now pair the Mac app with BT Paste Ducker and its
  complete modified source. The public 0.1.x builds remain unchanged.

Experimental: the interrupted live Turkish-Q/focus test did not pass. Local
translation, protocol and host tests are not a replacement for hardware validation.

## 0.1.0 - 2026-11-01

- Initial native Mac and Flipper Zero clipboard bridge.
- Authenticated Bluetooth LE text transfer with USB keyboard output.
- US and Turkish Q layouts; validated ASCII, tabs, and line breaks.
- Native editor, file import, clipboard loading, transfer status, and cancellation.
- Redesigned compact Flipper status screen with separated title and detail lines.
- Custom macOS application icon and universal Apple Silicon/Intel bundle.
- Tests, CI, release checksums, and third-party Homebrew tap packaging.

Known limits: 3071 text bytes per request; no arbitrary Unicode; early release is
ad-hoc signed and not Apple-notarized. Broader hardware edge-case testing remains.
