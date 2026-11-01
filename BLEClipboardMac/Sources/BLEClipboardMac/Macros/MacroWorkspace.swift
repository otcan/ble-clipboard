import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroJSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct MacroWorkspace: View {
    @ObservedObject var bluetooth: DuckerBluetooth
    @ObservedObject var library: MacroLibrary
    @State private var selection: UUID?
    @State private var search = ""
    @State private var quickText = ""
    @State private var quickTarget = TargetSystem.macOS
    @State private var quickLayout = MacroLayout.us
    @State private var editing: SavedMacro?
    @State private var reviewing: SavedMacro?
    @State private var deleting: SavedMacro?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportFile = MacroJSONFile(data: Data())
    @State private var error: String?

    private var selected: SavedMacro? { library.macros.first { $0.id == selection } }
    private var visible: [SavedMacro] { library.macros.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Button { selection = nil } label: { Label("Quick Paste", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("quick-paste")
                    Section("Macros") {
                        if visible.isEmpty { Text("No matching macros").foregroundStyle(.secondary) }
                        ForEach(visible) { macro in
                            Label(macro.name, systemImage: "command.square")
                                .tag(macro.id)
                                .contextMenu {
                                    Button("Edit") { editing = macro }
                                    Button("Duplicate") { attempt { selection = try library.duplicate(macro) } }
                                    Button("Delete", role: .destructive) { deleting = macro }
                                }
                        }
                    }
                }
                .searchable(text: $search, placement: .sidebar)
                Divider()
                HStack {
                    icon("New Macro", "plus") { editing = SavedMacro(name: "New Macro", steps: [.init(.text)]) }
                        .accessibilityIdentifier("new-macro")
                    Spacer()
                    icon("Import Macros", "square.and.arrow.down") { importing = true }
                    icon("Export Library", "square.and.arrow.up") {
                        attempt { exportFile = MacroJSONFile(data: try library.exportData()); exporting = true }
                    }
                }
                .padding(12)
            }
            .navigationTitle("BLE Clipboard")
            .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 290)
        } detail: {
            VStack(spacing: 0) {
                connectionBar
                Divider()
                if let message = library.error {
                    HStack {
                        Label(message, systemImage: "exclamationmark.triangle")
                        Button("Recover Backup") { attempt { try library.recoverBackup() } }
                    }
                    .font(.callout).padding()
                }
                if let macro = selected { macroDetail(macro) }
                else { quickPaste }
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: bluetooth.isBusy ? "keyboard" : bluetooth.isReady ? "checkmark.circle" : "circle.dashed")
                    Text(bluetooth.status).lineLimit(3).textSelection(.enabled)
                    Spacer(minLength: 8)
                    if bluetooth.isBusy {
                        ProgressView(value: bluetooth.progress).frame(width: 75)
                        icon("Stop Output", "stop.fill") { bluetooth.cancel() }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minHeight: 38)
                .padding(.horizontal, 18)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.teal)
        .sheet(item: $editing) { macro in
            MacroEditor(initial: macro) { changed in try library.save(changed); selection = changed.id }
        }
        .sheet(item: $reviewing) { macro in
            MacroRunReview(macro: macro, bluetooth: bluetooth)
        }
        .alert("Unable to Complete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("Delete \(deleting?.name ?? "macro")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let macro = deleting { attempt { try library.remove(macro.id); selection = nil } }
                deleting = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            attempt {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                selection = try library.importData(MacroLibrary.read(url))
            }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: "BLE-Clipboard-Macros") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer").font(.title3)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(bluetooth.isReady ? .teal : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(bluetooth.deviceName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(bluetooth.isReady ? "Ducker connected" : "Bluetooth").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            Label("USB target", systemImage: "cable.connector").font(.system(size: 12))
            Spacer(minLength: 8)
            if !bluetooth.candidates.isEmpty && !bluetooth.isConnected {
                Menu("Devices") {
                    ForEach(bluetooth.candidates) { item in Button(item.name) { bluetooth.connect(item.id) } }
                }.fixedSize()
            }
            Button {
                if bluetooth.isConnected || bluetooth.isScanning { bluetooth.disconnect() }
                else { bluetooth.scan() }
            } label: {
                Image(systemName: bluetooth.isConnected ? "power" : bluetooth.isScanning ? "stop.fill" : "antenna.radiowaves.left.and.right")
                    .frame(width: 26, height: 26)
            }
            .help(bluetooth.isConnected ? "Disconnect" : bluetooth.isScanning ? "Stop Searching" : "Connect to Flipper")
            .accessibilityLabel(bluetooth.isConnected ? "Disconnect" : "Connect to Flipper")
            .disabled(bluetooth.isBusy)
        }
        .padding(18)
    }

    private var quickPaste: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Paste").font(.system(size: 22, weight: .semibold))
                Spacer()
                icon("Load Clipboard", "doc.on.clipboard") { quickText = NSPasteboard.general.string(forType: .string) ?? "" }
                    .accessibilityIdentifier("load-clipboard")
                icon("Clear Text", "trash") { quickText = "" }.disabled(quickText.isEmpty)
            }
            TextEditor(text: $quickText)
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel("Text to Type")
            HStack {
                Picker("Target", selection: $quickTarget) {
                    ForEach(TargetSystem.allCases) { Text($0.rawValue).tag($0) }
                }.frame(maxWidth: 220)
                Picker("Layout", selection: $quickLayout) {
                    ForEach(MacroLayout.allCases) { Text($0.title).tag($0) }
                }.frame(maxWidth: 180)
                Spacer()
            }
            HStack {
                Text("\(quickText.utf8.count.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    reviewing = SavedMacro(name: "Quick Paste", target: quickTarget, layout: quickLayout, steps: [.init(.text, quickText)])
                } label: { Label("Review & Run", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(quickText.isEmpty || bluetooth.isBusy)
                    .accessibilityIdentifier("review-quick-paste")
            }
        }
        .padding(24)
    }

    private func macroDetail(_ macro: SavedMacro) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(macro.name).font(.system(size: 22, weight: .semibold)).textSelection(.enabled)
                    Text("\(macro.target.rawValue) · \(macro.layout.title) · \(macro.steps.count) steps")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                icon("Edit Macro", "pencil") { editing = macro }.accessibilityIdentifier("edit-macro")
                Menu {
                    Button("Duplicate") { attempt { selection = try library.duplicate(macro) } }
                    Button("Export Macro") { attempt { exportFile = MacroJSONFile(data: try library.exportData([macro.id])); exporting = true } }
                    Divider()
                    Button("Delete", role: .destructive) { deleting = macro }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }.menuStyle(.borderlessButton).fixedSize()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", index + 1)).foregroundStyle(.tertiary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.kind.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                Text(step.kind == .delay ? "\(step.milliseconds) ms" : step.value)
                                    .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(.vertical, 15)
                        Divider()
                    }
                }
            }
            HStack {
                Text(macro.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { reviewing = macro } label: { Label("Review & Run", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(bluetooth.isBusy)
                    .accessibilityIdentifier("review-macro")
            }
        }.padding(24)
    }

    private func icon(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24) }
            .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

private struct MacroEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedMacro
    @State private var error: String?
    let save: (SavedMacro) throws -> Void
    init(initial: SavedMacro, save: @escaping (SavedMacro) throws -> Void) {
        _draft = State(initialValue: initial)
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Macro").font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try save(draft); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).accessibilityIdentifier("save-macro")
            }.padding(18)
            Divider()
            Form {
                Section {
                    TextField("Name", text: $draft.name).accessibilityIdentifier("macro-name")
                    Picker("Target", selection: $draft.target) {
                        ForEach(TargetSystem.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Layout", selection: $draft.layout) {
                        ForEach(MacroLayout.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Steps") {
                    ForEach($draft.steps) { $step in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Picker("Step", selection: $step.kind) { ForEach(MacroStep.Kind.allCases) { Text($0.title).tag($0) } }
                                Spacer()
                                Button { move(step.id, -1) } label: { Image(systemName: "arrow.up") }.help("Move Up")
                                Button { move(step.id, 1) } label: { Image(systemName: "arrow.down") }.help("Move Down")
                                Button(role: .destructive) { draft.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "trash") }.help("Delete Step")
                            }
                            if step.kind == .delay {
                                Stepper("\(step.milliseconds) ms", value: $step.milliseconds, in: 1...30_000, step: 50)
                            } else if step.kind == .chord {
                                TextField("Key combination", text: $step.value).font(.system(.body, design: .monospaced))
                            } else {
                                TextEditor(text: $step.value).font(.system(.body, design: .monospaced)).frame(minHeight: 66)
                                if step.kind == .template {
                                    Menu {
                                        Button("Clipboard") { step.value += "{{clipboard}}" }
                                        Button("Timestamp") { step.value += "{{timestamp}}" }
                                        ForEach(draft.parameters) { item in Button(item.label) { step.value += "{{\(item.id)}}" } }
                                    } label: { Label("Insert Parameter", systemImage: "curlybraces") }.fixedSize()
                                }
                            }
                        }.padding(.vertical, 6)
                    }
                    Button { draft.steps.append(.init(.text)) } label: { Label("Add Step", systemImage: "plus") }.disabled(draft.steps.count >= 128)
                }
                Section("Run Parameters") {
                    ForEach(draft.parameters.indices, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $draft.parameters[index].id)
                            TextField("Label", text: $draft.parameters[index].label)
                            Button { draft.parameters.remove(at: index) } label: { Image(systemName: "trash") }.help("Delete Parameter")
                        }
                    }
                    Button {
                        var number = draft.parameters.count + 1
                        while draft.parameters.contains(where: { $0.id == "field\(number)" }) { number += 1 }
                        draft.parameters.append(.init(id: "field\(number)", label: "Field \(number)"))
                    } label: { Label("Add Parameter", systemImage: "plus") }.disabled(draft.parameters.count >= 32)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
        }
        .frame(width: 650, height: 680)
    }
    private func move(_ id: UUID, _ direction: Int) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }), draft.steps.indices.contains(index + direction) else { return }
        draft.steps.swapAt(index, index + direction)
    }
}

private struct MacroRunReview: View {
    @Environment(\.dismiss) private var dismiss
    let macro: SavedMacro
    @ObservedObject var bluetooth: DuckerBluetooth
    @State private var clipboard: String
    @State private var date = Date()
    @State private var values: [String: String] = [:]
    @State private var confirmed = false
    @State private var hideBeforeOutput = false

    init(macro: SavedMacro, bluetooth: DuckerBluetooth) {
        self.macro = macro
        self.bluetooth = bluetooth
        let needsClipboard = macro.steps.contains { $0.kind == .template && $0.value.contains("{{clipboard}}") }
        _clipboard = State(initialValue: needsClipboard ? (NSPasteboard.general.string(forType: .string) ?? "") : "")
    }

    private var compiled: Result<CompiledMacro, Error> {
        Result { try MacroCompiler.compile(macro, context: .init(clipboard: clipboard, date: date, parameters: values),
                                          limit: bluetooth.capacity > 0 ? bluetooth.capacity : MacroCompiler.maximumBytes) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(macro.name).font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            LabeledContent("USB Target", value: "\(macro.target.rawValue) / \(macro.layout.title)")
            LabeledContent("Flipper", value: bluetooth.isReady ? bluetooth.deviceName : "Not connected")
            if !macro.parameters.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(macro.parameters) { parameter in
                            TextField(parameter.label, text: Binding(get: { values[parameter.id] ?? "" }, set: { values[parameter.id] = $0 }))
                        }
                    }
                }.frame(height: min(CGFloat(macro.parameters.count * 32), 160))
            }
            Divider()
            switch compiled {
            case .success(let output):
                ScrollView {
                    Text(output.preview.joined(separator: "\n\n"))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                Text("\(output.bytes.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.red)
                Spacer()
            }
            Toggle("The intended USB target and input field are focused", isOn: $confirmed)
            Toggle("Hide this app before output", isOn: $hideBeforeOutput)
            HStack {
                Label("Line breaks send Enter; output cannot be undone", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    if case .success(let output) = compiled { bluetooth.run(output, hideApp: hideBeforeOutput); dismiss() }
                } label: { Label("Run on USB", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
                    .accessibilityIdentifier("run-confirmed")
            }
        }.padding(24).frame(width: 650, height: 570)
    }
    private var canRun: Bool {
        guard confirmed, bluetooth.isReady, !bluetooth.isBusy, case .success = compiled else { return false }
        return true
    }
}
