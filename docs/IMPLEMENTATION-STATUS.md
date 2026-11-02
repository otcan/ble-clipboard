# Macros and Mac App Store implementation

Work is isolated on `feature/macros-store`; the main worktree and connected
Flipper must not be interrupted by development builds.

## Milestones

- [x] Preserve the working baseline in a separate Git worktree.
- [x] Pin and host-test Ducker; build for firmware 1.5.1 / API 88.2 (not hardware validation).
- [x] Implement a native, tested TTF1 adapter and safe literal serialization.
- [x] Implement local macro persistence, parameters, previews, and starter macros.
- [x] Integrate the library into the native Mac interface.
- [x] Add the sandboxed Xcode Store target and validate an unsigned universal archive.
- [x] Run protocol, engine, persistence, and UI tests.
- [ ] Perform real-device integration and interruption tests when the device is available.
- [ ] Resolve Store licensing/rights and distribution metadata.
- [ ] Upload a signed TestFlight build after distribution signing is configured.
- [ ] Complete external beta, review demonstration, and owner approval.
- [ ] Submit for App Review and verify the Store-installed release.

## Non-automatable gates

No ownership or licensing consent is inferred from a repository's existence.
The existing GPL notices remain in place pending a rights review; no GPL
implementation code is copied into the native Mac adapter. Store compatibility
must be reviewed before submission. The Account Holder must personally accept
agreements and approve banking/tax details, pricing, and release. Tester feedback,
physical hardware evidence, and Apple's approval cannot be fabricated.

## Evidence and remaining boundary

Local Swift tests: 28 passing, including all 28 layout serialization cases,
explicit Bluetooth permission-state diagnostics and missing intermediate-status
handling.
The earlier Xcode run passed 24 unit plus 2 UI checks
(create/edit and offline review). Host C tests cover upstream protocol/HID plus
the Mac serialization contract. Ducker is pinned, unmodified and builds as a FAP
for API 88.2. The universal archive contains arm64/x86_64, icon, license/privacy
resources and the required Bluetooth usage description. Debug's separate bundle
identifier avoids the existing app. UI testing explicitly disables Bluetooth.
The original SwiftPM/direct-download app keeps its legacy entry point; only
the distinct `MACROS_STORE` target uses the new UI/backend.

The initial implementation left the parent worktree, installed Mac app and
connected Flipper unchanged. On the owner's subsequent request, Ducker was
installed separately on the Flipper and verified by USB read-back checksum.
The original app and firmware were not overwritten. Live discovery succeeded,
but no hardware end-to-end typing pass is claimed. After macOS authorization,
both clients reproduced a missing TTF1 response with the upstream serial profile.
The separate compatibility FAP was installed and checksum-verified; it fixes the
observed RPC/profile conflict and both clients now complete TTF1 setup.
After exclusive control was granted, a controlled 28-byte USB sample matched
exactly in the dedicated capture app. Completion reporting then timed out;
a follow-up status-reliability build passes host tests, is installed with a
matching USB read-back, and now reports native completion without disconnecting.
Its first repeat target capture was empty, and helper instrumentation showed an
inactive target window. After the owner focused the capture, exact 28-byte and
4,160-byte sends passed with completion and a retained connection. Parameterized
two-field output, cancellation during a 30-second delay and a bonded reconnect
without replay also passed. The full-ASCII sample exposed a Turkish-Q punctuation
and dead-key mismatch on this Mac; that and the broader hardware matrix remain
open. Native JSON fixture import was also exercised successfully.
See `HARDWARE-VALIDATION.md` for the exact checkpoint. The capture helper is a
separate, non-shipping development tool, not a Store entitlement change.
The local keychain has development/Developer ID identities, but no suitable
Store distribution identity. No signing certificate, profile, App Store record,
price schedule, TestFlight upload or review submission has been created.

Store metadata/privacy/review drafts and a gated archive script are prepared.
`Store/metadata/RELEASE-CHECKLIST.md` records the still-unverified acceptance
matrix; do not turn these draft documents into a claim that deployment is done.
