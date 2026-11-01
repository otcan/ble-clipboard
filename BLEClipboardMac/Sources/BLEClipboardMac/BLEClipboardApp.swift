import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct BLEClipboardApp: App {
    @StateObject private var bluetooth = BluetoothManager()

    var body: some Scene {
        WindowGroup("BLE Clipboard") {
            ClipboardView(bluetooth: bluetooth)
                .frame(minWidth: 560, minHeight: 540)
        }
        .defaultSize(width: 660, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        Settings {
            ClipboardSettings()
        }
    }
}

private enum ClipboardStyle {
    static let accent = Color(red: 0.93, green: 0.34, blue: 0.09)
}

struct ClipboardView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @State private var text = ""
    @State private var importing = false
    @State private var importError: String?
    @FocusState private var editorFocused: Bool
    @AppStorage("targetKeyboardLayout") private var layout = 0
    @AppStorage("hideAfterSending") private var hideAfterSending = true

    private var validationError: String? {
        guard !text.isEmpty else { return nil }
        do {
            _ = try USBText.payload(text, layout: UInt8(clamping: layout))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canSend: Bool {
        bluetooth.isReady && !bluetooth.isBusy && !text.isEmpty && validationError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            connectionRoute
            Divider()
            composer
            Divider()
            actionBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(ClipboardStyle.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                text = try ClipboardFile.read(url)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("BLE Clipboard")
                    .font(.system(size: 19, weight: .semibold))
                Label("Bluetooth to USB", systemImage: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 6) {
                Image(systemName: bluetooth.isReady ? "lock.shield.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(bluetooth.isReady ? Color.green : Color.secondary)
                Text(bluetooth.isReady ? "Paired" : bluetooth.isScanning ? "Searching" : "Not connected")
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize()
            }
            Button {
                (bluetooth.isReady || bluetooth.isScanning || bluetooth.isBusy)
                    ? bluetooth.disconnect() : bluetooth.scan()
            } label: {
                Image(systemName: bluetooth.isReady ? "power" : bluetooth.isScanning ? "stop.fill" : "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(bluetooth.isReady ? "Disconnect Flipper" : bluetooth.isScanning ? "Stop searching" : "Connect to Flipper")
            .accessibilityLabel(bluetooth.isReady ? "Disconnect Flipper" : "Connect to Flipper")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
    }

    private var connectionRoute: some View {
        HStack(spacing: 18) {
            routeNode("This Mac", symbol: "laptopcomputer", subtitle: "SOURCE", active: true)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            routeNode(bluetooth.deviceName.isEmpty ? "Flipper Zero" : bluetooth.deviceName,
                      symbol: "antenna.radiowaves.left.and.right",
                      subtitle: "BLUETOOTH", active: bluetooth.isReady)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            routeNode("USB target", symbol: "cable.connector", subtitle: "KEYBOARD", active: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func routeNode(_ title: String, symbol: String, subtitle: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .frame(width: 23)
            VStack(alignment: .leading, spacing: 3) {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("TEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(text.utf8.count.formatted()) / 3,071 bytes")
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(validationError == nil ? Color.secondary : Color.red)
                    .padding(.trailing, 7)
                editorTool("Open Text File", symbol: "folder") { importing = true }
                editorTool("Load Clipboard", symbol: "doc.on.clipboard") {
                    text = NSPasteboard.general.string(forType: .string) ?? ""
                    importError = nil
                }
                editorTool("Clear Text", symbol: "trash") {
                    text = ""
                    importError = nil
                }
                .disabled(text.isEmpty)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 165)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(editorFocused ? ClipboardStyle.accent.opacity(0.65) : Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .focused($editorFocused)
                .accessibilityLabel("Text to type over USB")

            HStack(alignment: .top, spacing: 6) {
                let error = importError ?? validationError
                Image(systemName: error == nil ? (bluetooth.isReady ? "checkmark.circle" : "circle.dashed") : "exclamationmark.circle.fill")
                    .foregroundStyle(error == nil ? Color.secondary : Color.red)
                Text(error ?? bluetooth.status)
                    .font(.system(size: 11))
                    .foregroundStyle(error == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 16, alignment: .topLeading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 17)
        .padding(.bottom, 15)
    }

    private func editorTool(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .disabled(bluetooth.isBusy)
    }

    private var actionBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Target layout")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Picker("Target layout", selection: $layout) {
                        Text("US").tag(0)
                        Text("Turkish Q").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .disabled(bluetooth.isBusy)
                }
                Spacer()
                Button { bluetooth.cancel() } label: {
                    Image(systemName: "stop.fill").frame(width: 26, height: 26)
                }
                .help("Cancel typing")
                .accessibilityLabel("Cancel typing")
                .opacity(bluetooth.isBusy ? 1 : 0)
                .disabled(!bluetooth.isBusy)
                Button {
                    bluetooth.type(text, layout: UInt8(clamping: layout), hideOnAccept: hideAfterSending)
                } label: {
                    Label(bluetooth.isBusy ? "Sending..." : "Send to USB", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 118, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
            }
            HStack(spacing: 5) {
                if bluetooth.isBusy {
                    ProgressView(value: bluetooth.transferProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 74)
                    Text(bluetooth.transferProgress < 1 ? "Transferring" : "USB output in progress")
                } else if let time = bluetooth.lastDeliveryAt {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(bluetooth.lastDeliveryBytes) bytes sent")
                    Text(time, style: .time).foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "keyboard")
                    Text(bluetooth.lastResult.isEmpty ? "No transfers yet" : bluetooth.lastResult)
                }
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(height: 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

private struct ClipboardSettings: View {
    @AppStorage("hideAfterSending") private var hideAfterSending = true
    var body: some View {
        Form {
            Toggle("Hide after sending", isOn: $hideAfterSending)
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 110)
    }
}
