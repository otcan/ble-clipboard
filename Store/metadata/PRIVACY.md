# Privacy policy draft

This draft describes the current source, not an already published Store service.
Review it against the exact shipping binary, add the accountable publisher and
effective date, then publish it at the Store listing's public privacy-policy URL.

BLE Clipboard does not use analytics, advertising, tracking or a developer-run
server. It does not send clipboard text, macro definitions or run arguments to
the developer. Its runtime data transfer is to the Flipper the user selects over
Bluetooth, then to the USB target through keyboard input.

Clipboard text is read on an explicit Load Clipboard action or when preparing a
macro that references the clipboard. The app does not monitor clipboard changes.
Run snapshots and prompted values are kept in memory and are not intentionally
written to the Mac library. Local crash reports and operating-system behavior
remain controlled by Apple/macOS and the user's settings.

Saved macro definitions and one recovery backup are stored locally in the app's
sandbox. Literal text saved in a definition is persisted. Exported JSON includes
the selected definitions and is not encrypted. Users choose whether and where
to share exports. Local files can be included in device/OS backups.

The Flipper/firmware manages Bluetooth bonding keys. The separate Ducker app
keeps a RAM replay history and may write large transfers to a temporary SD file.
The Mac app does not provide a secure-erasure or password-vault guarantee.
Do not use it to handle secrets on devices/storage you do not trust.

Users can delete individual macros in the library, remove exported copies and
remove the app's container to erase its local library/backup. Deleting a macro
does not securely erase prior backup, export, target, Flipper or OS backup data.
The publisher does not have a server copy to retrieve or delete.

Opening a source/support link uses the user's browser and the destination's
privacy policy. Do not include sensitive clipboard content in public issues.

Draft contact route: https://github.com/otcan/ble-clipboard/issues.
Publisher identity and effective date: **required before publication**.

Draft App Store privacy answers: no developer collection or tracking, subject
to a final audit of the shipping build and any added dependencies. The bundled
privacy manifest declares no tracking/collected data/required-reason API use in
the new Store target. Re-audit if runtime code or SDKs change.
