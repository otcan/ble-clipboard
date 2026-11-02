# App Review instructions draft

This app requires a physical Flipper Zero and a USB target. No developer account
or login is required. A reviewer cannot validate USB output on a simulator alone.

Before submission, attach a real video showing the shipping Mac app/build,
Flipper firmware/app version, pairing prompts, USB cable to the target, typed
output, and cancellation. Publish permanent, accessible source/build instructions
for the required Flipper application. Offer reviewer hardware/access arrangements
as required by Apple; do not claim the accessory is included with the purchase.

Review path:

1. Open the matching **BT Paste Ducker** compatibility app on the Flipper, with
   its Bluetooth enabled. Do not substitute the unmodified upstream FAP for the
   official 1.5.1 test configuration; see the compatibility build instructions.
2. Launch the Mac app; press Connect, choose the correct Flipper under Devices,
   and approve any pairing prompts on both devices.
3. Connect Flipper USB to a second computer with a plain text editor focused.
   Use matching US layout initially. No target-side software is required.
4. Select Timestamp, Review & Run, inspect output and confirm focus. Run on USB.
5. Test a saved snippet containing literal `[ENTER]`; it must type those
   characters, not an Enter command. Newlines themselves do send Enter.
6. Use Fill Two Fields with two harmless values; it tabs once without submitting.
7. Test Stop during output. This backend disconnects BLE to cancel; input already
   sent cannot be undone. It does not automatically reconnect or replay.

Current development pin: Ducker commit
`9d706967f7006702c9db3368235e6b6495176a46`, official firmware 1.5.1/API 88.2 build.
Replace with exact hardware-verified release identifiers at submission time.
The compatibility source overlay is in `DuckerCompatibility/`; its complete
generated source archive accompanies the FAP. Only BLE setup is verified at the
current checkpoint, not the complete physical demonstration.

No accessibility permission, screen capture, root helper, downloaded executable,
Mac shell execution, built-in updater or target OS clipboard access is used by
this app. Macro commands represent USB keyboard input on an authorized target.
The app uses only Apple's public CoreBluetooth/SwiftUI/AppKit APIs.

Video URL, tested hardware, signed build number and reviewer contact:
**not yet available; do not submit until completed**.
