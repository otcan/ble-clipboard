# 0.5.2 Implementation Status

0.5.2 adds Info & Companions, guarded version-pinned downloads, read-only device
version reporting and an on-device About/release QR screen. It preserves the
0.5.1 movement guard and macro/snapshot formats. After explicit owner readiness
on 2026-11-03, both 0.5.2 apps were installed with 0.5.1 backups. Mac signature,
architectures, version and full Flipper readback/checksum checks passed. The
installed Mac Info panel showed 0.5.2; before publication its release check returned
Not published yet with both downloads disabled. The macro library was unchanged.
The Flipper app was left idle/closed; no live input was generated. That installation
used an ad-hoc development build. Public release assets are finalized separately;
use their checksums and signing verification, not an old local build receipt.

The publication candidate now has a read-only --info launch path and a compact
QR code button. After owner approval, a temporary FAP was used for genuine
qFlipper Info/QR exports without Bluetooth, HID or library setup. It was removed
after capture; full installed-FAP readback still matched the original 0.5.2.
See the catalog-capture evidence in HARDWARE-VALIDATION.md. Public artifacts are
not installed automatically over the owner's running app.

## Installed 0.5.1 Checkpoint

0.5.1 adds a tested HID adapter that clears inherited mouse buttons before each
movement and releases keyboard/mouse state at startup, Stop and exit. A failed
button-up report prevents movement. The protocol and saved jobs are unchanged.
After explicit owner readiness on 2026-11-03, both 0.5.1 apps were installed with
0.5.0 backups. Mac version/signature/architectures and full Flipper readback were
verified; the Mac About panel reports 0.5.1 (1). Macro definitions and saved SD
jobs are unchanged. No live 0.5.1 input test has been run.

Worktree branch: `feature/independent-0.3.0`. The previous 0.2.0 work was preserved
in an ignored local source archive before replacement. The separate main worktree,
submitted 0.1.1 artifacts, device firmware and bonds are untouched. After owner
readiness at the previous checkpoint on 2026-11-03, the pair was updated from 0.4.0 to 0.5.0 with
backups and file verification, without executing a hardware job. The Mac runs
from /Applications; its existing Mouse Jiggle preset now uses ranged Move Mouse
and Repeat, preserving its ID, target, layout and eight-hour duration. Saved
Flipper snapshots are unchanged until explicitly resent. The 0.3.0 and 0.4.0
source/artifacts remain archived locally.

## Implemented

- One native Mac app: Quick Paste, text-file import, saved macros, parameters,
  templates, keys, delays, run review, library import/export and recovery.
- Saved JSON schema/IDs preserved; standard and Store targets share the same UI.
- Independent authenticated BLE profile and version-4 binary transport.
- Generic Move Mouse with fixed/ranged offsets and a one-level timed Repeat body;
  the mouse preset now uses those actions. Range values are sampled on Flipper.
- Old schema 1/2 and saved binary jobs stay readable; new definitions use schema 3.
- Native mouse jiggle, up to 24 hours, with explicit standalone continuation,
  physical Stop and elapsed/remaining timer. Normal jobs still stop on BLE loss.
- A 20-entry plaintext SD library for compiled macros and clipboard snapshots,
  explicit save without execution, local browse/Run/Delete confirmations,
  checksummed metadata/body, atomic replacement and backup recovery.
- Reconnect attaches remote Stop to an active autonomous job without replay.
- Acknowledged 512-byte uploads, CRC-32, job IDs and full preflight before Execute.
- Own typed-program engine, nonblocking delays, progress, cancellation without
  disconnecting, key release, timeouts and no automatic replay.
- 4 KiB RAM path plus temporary SD storage for programs up to 65,536 bytes.
- 28-layout catalog and experimental native Turkish letters; built-in US and
  macOS Turkish-Q mappings, without script tags or an external backend.
- Removed the vendor gitlink/submodule configuration, compatibility patches,
  script transport/interpreter dependency and their build/test scripts.
- Matching Mac/FAP packaging, corresponding source and source fingerprints.

## Local Evidence

Swift unit tests cover saved macros and recovery, binary records, invalid input,
all layout/target IDs, CRC/frame fragmentation, execution gating, stale/duplicate
responses, cancellation during upload/commit/execution and capacity limits.

The sanitizer-enabled host tests compile the actual independent C engine/server.
They exercise complete Mac-generated wire fixtures, maximum-size jobs, literal
command-looking text, Turkish UTF-8, shortcuts/delays, queue expiry, malformed
programs, SD/storage/TX/USB/BLE failure paths, immediate cancellation and no replay.
The C-emitted ASCII/Turkish HID reports match Apple's keyboard translation on
three keyboard types. These checks do not interact with a USB device.

New checks simulate eight hours and timer rollover, offline physical Stop, USB
loss and no restart, reconnect/remote Stop, compact mouse records, old/new JSON,
save-only gating and SD persistence/corruption/interrupted-replacement/slot-limit.
These are host-clock/filesystem tests, not a physical multi-hour soak.

Both Mac and Flipper source compile locally. Release output is built separately;
no signing credentials, notarization submission, public tag or release is created
by implementation or tests. See the final build artifacts/checksums for the exact
packaged result rather than treating old preview products as current.

## Still Open

Fresh physical BLE/USB/SD verification, target focus and shortcuts, first pairing,
other layouts/OSes, sleep/power/cable interruptions and install/upgrade behavior.
Old backend device results are history, not a pass for this replacement.

Store licensing/rights review, owner-confirmed seller/price/identifiers, agreements,
permanent privacy/support URLs, proper Store signing/profile, beta feedback,
review demonstration and Apple approval also remain open. Do not claim Store
approval or full hardware certification, or reuse an old notarization ticket
for a different binary.
