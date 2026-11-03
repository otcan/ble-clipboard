import AppKit
import SwiftUI

@main
struct BLEClipboardApp: App {
    @StateObject private var bluetooth = ClipboardBluetooth(preview: CompanionRelease.isPreview)
    @StateObject private var library = MacroLibrary(url: CompanionRelease.isPreview
        ? FileManager.default.temporaryDirectory.appendingPathComponent("ble-clipboard-ui-\(UUID()).json") : nil)

    var body: some Scene {
        WindowGroup("BLE Clipboard") {
            MacroWorkspace(bluetooth: bluetooth, library: library)
                .frame(minWidth: 860, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    bluetooth.disconnect()
                }
        }
        .defaultSize(width: 1020, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button("Info & Companions") { NotificationCenter.default.post(name: .showCompanionInfo, object: nil) }
            }
        }
        Settings {
            Form {
                LabeledContent("Execution engine", value: "BLE Clipboard \(CompanionRelease.currentVersion) / Protocol 4")
                LabeledContent("License", value: "GNU GPL v3; see source notices")
                Link("Source and Notices", destination: URL(string: "https://github.com/otcan/ble-clipboard")!)
                LicenseNoticesButton()
            }
            .padding(24)
            .frame(width: 440)
        }
    }
}
