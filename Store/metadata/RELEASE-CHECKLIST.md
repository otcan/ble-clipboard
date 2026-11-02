# Release acceptance

Unchecked means not verified, not optional. Attach evidence to a release issue.

## Engineering

- [ ] Swift unit tests and Ducker host/serialization contract tests pass in CI.
- [x] Local sandboxed UI tests: create/edit/review, disconnected run disabled.
- [x] Local unsigned universal archive validated.
- [ ] Signed Store archive validated.
- [ ] Sandbox entitlements, Bluetooth description, icon and privacy resources checked.
- [ ] JSON import/export and backup recovery tested with real file pickers.
- [ ] Light/dark, narrow window, long names, large text and VoiceOver checked.
- [ ] Clean install and upgrade preserve definitions and leave corrupt files intact.

## Physical device matrix

- [x] One official 1.5.1/API 88.2 device: exact 28-byte and 4,160-byte captures; completion and retained connection.
- [x] Same Mac: parameterized two-field output, Stop during a 30-second delay, bonded reconnect without replay.
- [ ] Resolve Turkish QWERTY PC punctuation/dead-key mismatch observed in the full-ASCII sample.
- [ ] First pairing shows expected two-device confirmation; wrong/unpaired Mac denied.
- [ ] Reconnect works, with no replay and no stale queued output.
- [ ] macOS, Windows and Linux targets: supported shortcuts and US output verified.
- [ ] Turkish Q asset present/missing/wrong layout cases verified.
- [ ] Literal brackets, all printable ASCII, tabs, LF/CRLF and non-ASCII rejection.
- [ ] Small, 4096-byte and maximum/near-maximum escaped transfers (SD path).
- [ ] Stop during layout, transfer, USB wait, key combination and long delay.
- [ ] USB unplug, BLE loss, Bluetooth off, Mac sleep/quit and Flipper power cycle.
- [ ] No stuck modifiers after interruptions; target inspected before retries.
- [ ] App remains connected after successful runs; completion is HID submission only.
- [ ] Other Flipper app/official companion active: useful error, no accidental execution.

## Distribution

- [ ] Rights/licensing review recorded and recipient/source obligations satisfied.
- [ ] Owner confirms seller/team, bundle ID, app name, SKU and price/territories.
- [ ] Account Holder confirms paid agreements, tax/banking and required declarations.
- [ ] Permanent privacy/support/source URLs and immutable source release available.
- [ ] Encryption, age rating, privacy and accessibility declarations audited.
- [ ] Correct Store signing/profile/build number; validation and upload successful.
- [ ] Internal beta feedback recorded; external beta review completed if applicable.
- [ ] Physical review video and reviewer instructions verified accessible.
- [ ] App Review approved; owner approves manual release.
- [ ] Store-installed app tested for receipt/install, Bluetooth permission and update.

No beta feedback, hardware result, legal clearance or Apple approval can be
generated as a substitute for completing these checks.
