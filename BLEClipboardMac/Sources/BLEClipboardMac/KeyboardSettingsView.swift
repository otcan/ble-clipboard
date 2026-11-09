import SwiftUI

struct KeyboardSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bluetooth: ClipboardBluetooth

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Flipper Keyboard", systemImage: "keyboard").font(.title3.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Close").accessibilityLabel("Close")
            }
            Form {
                Picker("USB Target", selection: Binding(get: { bluetooth.keyboardSettings.target }, set: { bluetooth.changeKeyboard(target: $0) })) {
                    ForEach(TargetSystem.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Keyboard Layout", selection: Binding(get: { bluetooth.keyboardSettings.layout }, set: { bluetooth.changeKeyboard(layout: $0) })) {
                    ForEach(KeyboardLayout.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Use for Saved Runs on Flipper", isOn: Binding(get: { bluetooth.keyboardSettings.useForSavedRuns }, set: { bluetooth.changeKeyboard(useForSavedRuns: $0) }))
                    .disabled(bluetooth.isReady && !bluetooth.keyboardSyncSupported)
            }
            .disabled(!bluetooth.canChangeKeyboard)
            Divider()
            HStack(alignment: .top) {
                Text(bluetooth.keyboardStatus).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if bluetooth.keyboardSyncPending { ProgressView().controlSize(.small) }
                Button { bluetooth.refreshKeyboard() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh Flipper Keyboard").accessibilityLabel("Refresh Flipper Keyboard")
                    .disabled(!bluetooth.isReady || !bluetooth.keyboardSyncSupported || bluetooth.keyboardSyncPending || bluetooth.isBusy)
            }
        }
        .padding(24).frame(width: 470)
    }
}
