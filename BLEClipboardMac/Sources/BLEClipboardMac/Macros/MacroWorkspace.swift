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

private struct MacroReviewRequest: Identifiable {
    let id = UUID()
    let macro: SavedMacro
    let destination: TransferDestination
}

struct MacroWorkspace: View {
    @ObservedObject var bluetooth: ClipboardBluetooth
    @ObservedObject var library: MacroLibrary
    @State private var selection: UUID?
    @State private var search = ""
    @State private var quickText = ""
    @State private var quickTarget = TargetSystem.macOS
    @State private var quickLayout = MacroLayout.us
    @State private var editing: SavedMacro?
    @State private var reviewing: MacroReviewRequest?
    @State private var deleting: SavedMacro?
    @State private var importing = false
    @State private var importingText = false
    @State private var exporting = false
    @State private var exportFile = MacroJSONFile(data: Data())
    @State private var error: String?
    @State private var showingInfo = false

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
                    icon("New Mouse Jiggle Macro", "computermouse") { editing = SavedMacro.mouseJiggler() }
                        .accessibilityIdentifier("new-mouse-jiggle")
                    Spacer()
                    icon("Import Macros", "square.and.arrow.down") { importingText = false; importing = true }
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
                        if bluetooth.remainingSeconds > 0 {
                            Text(Duration.seconds(bluetooth.remainingSeconds).formatted(.time(pattern: .hourMinuteSecond)))
                                .monospacedDigit().fixedSize()
                        }
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
        .toolbar {
            Button { showingInfo = true } label: { Image(systemName: "info.circle") }
                .help("Info & Companions").accessibilityLabel("Info & Companions")
                .accessibilityIdentifier("info-companions")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCompanionInfo)) { _ in showingInfo = true }
        .sheet(isPresented: $showingInfo) { CompanionInfoView(bluetooth: bluetooth) }
        .sheet(item: $editing) { macro in
            MacroEditor(initial: macro) { changed in try library.save(changed); selection = changed.id }
        }
        .sheet(item: $reviewing) { request in
            MacroRunReview(macro: request.macro, bluetooth: bluetooth, destination: request.destination)
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
        .fileImporter(isPresented: $importing, allowedContentTypes: importingText ? [.plainText] : [.json]) { result in
            attempt {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if importingText { quickText = try ClipboardFile.read(url, layout: quickLayout.wireID) }
                else { selection = try library.importData(MacroLibrary.read(url)) }
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
                Text(bluetooth.isReady ? "BLE Clipboard connected" : "Bluetooth").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            Label("USB target", systemImage: "cable.connector").font(.system(size: 12))
            Spacer(minLength: 8)
            if !bluetooth.candidates.isEmpty && !bluetooth.isConnected && !bluetooth.isConnecting {
                Menu("Devices") {
                    ForEach(bluetooth.candidates) { item in Button(item.name) { bluetooth.connect(item.id) } }
                }.fixedSize()
            }
            Button {
                if bluetooth.isConnected || bluetooth.isConnecting || bluetooth.isScanning { bluetooth.disconnect() }
                else { bluetooth.scan() }
            } label: {
                Image(systemName: bluetooth.isConnected ? "power" : bluetooth.isScanning || bluetooth.isConnecting ? "stop.fill" : "antenna.radiowaves.left.and.right")
                    .frame(width: 26, height: 26)
            }
            .help(bluetooth.isConnected ? "Disconnect" : bluetooth.isConnecting ? "Cancel Connection" : bluetooth.isScanning ? "Stop Searching" : "Connect to Flipper")
            .accessibilityLabel(bluetooth.isConnected ? "Disconnect" : bluetooth.isConnecting ? "Cancel Connection" : "Connect to Flipper")
            .disabled(bluetooth.isBusy && !bluetooth.standaloneActive)
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
                icon("Open Text File", "doc.text") { importingText = true; importing = true }
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
                }.frame(minWidth: 230, idealWidth: 250, maxWidth: 300)
                Spacer()
            }
            HStack {
                Text("\(quickText.utf8.count.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    reviewing = .init(macro: SavedMacro(name: "Clipboard Snapshot", target: quickTarget, layout: quickLayout,
                                                       steps: [.init(.text, quickText)]), destination: .save)
                } label: { Label("Send to Flipper", systemImage: "square.and.arrow.up") }
                    .disabled(quickText.isEmpty || bluetooth.isBusy)
                    .accessibilityIdentifier("save-quick-paste")
                Button {
                    reviewing = .init(macro: SavedMacro(name: "Quick Paste", target: quickTarget, layout: quickLayout,
                                                       steps: [.init(.text, quickText)]), destination: .run)
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
                                Text(step.summary)
                                    .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if step.kind == .repeatFor {
                                    ForEach(step.children ?? []) { child in
                                        Text("\(child.kind.title): \(child.summary)")
                                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                            .padding(.leading, 12)
                                    }
                                }
                            }
                        }.padding(.vertical, 15)
                        Divider()
                    }
                }
            }
            HStack {
                Text(macro.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { reviewing = .init(macro: macro, destination: .save) } label: { Label("Send to Flipper", systemImage: "square.and.arrow.up") }
                    .disabled(bluetooth.isBusy).accessibilityIdentifier("save-macro-flipper")
                Button { reviewing = .init(macro: macro, destination: .run) } label: { Label("Review & Run", systemImage: "play.fill") }
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

private struct MacroNumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number)
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 84).accessibilityLabel(title)
            Stepper(title, value: $value, in: range).labelsHidden().fixedSize()
        }
    }
}

private struct PrimitiveStepFields: View {
    @Binding var step: MacroStep
    let parameters: [MacroParameter]
    private func coordinate(_ title: String, get: @escaping () -> Int, set: @escaping (Int) -> Void) -> some View {
        MacroNumberField(title: title, value: Binding(get: get, set: { set(min(127, max(-127, $0))) }), range: -127...127)
    }
    var body: some View {
        if step.kind == .delay {
            MacroNumberField(title: "Delay (milliseconds)", value: Binding(get: { step.milliseconds },
                set: { step.milliseconds = min(30_000, max(1, $0)) }), range: 1...30_000)
        } else if step.kind == .moveMouse {
            Picker("Offsets", selection: Binding(get: { step.varyingMouse == true }, set: { step.varyingMouse = $0 })) {
                Text("Fixed").tag(false); Text("Range").tag(true)
            }.pickerStyle(.segmented)
            coordinate(step.varyingMouse == true ? "X minimum (HID units)" : "X (HID units)", get: { step.xMinimum }, set: { step.mouseXMinimum = $0 })
            if step.varyingMouse == true {
                coordinate("X maximum (HID units)", get: { step.xMaximum }, set: { step.mouseXMaximum = $0 })
            }
            coordinate(step.varyingMouse == true ? "Y minimum (HID units)" : "Y (HID units)", get: { step.yMinimum }, set: { step.mouseYMinimum = $0 })
            if step.varyingMouse == true {
                coordinate("Y maximum (HID units)", get: { step.yMaximum }, set: { step.mouseYMaximum = $0 })
            }
        } else if step.kind == .chord {
            TextField("Key combination", text: $step.value).font(.system(.body, design: .monospaced))
        } else if step.kind == .text || step.kind == .template {
            TextEditor(text: $step.value).font(.system(.body, design: .monospaced)).frame(minHeight: 66)
            if step.kind == .template {
                Menu {
                    Button("Clipboard") { step.value += "{{clipboard}}" }
                    Button("Timestamp") { step.value += "{{timestamp}}" }
                    ForEach(parameters) { item in Button(item.label) { step.value += "{{\(item.id)}}" } }
                } label: { Label("Insert Parameter", systemImage: "curlybraces") }.fixedSize()
            }
        }
    }
}

private struct MacroStepRow: View {
    @Binding var step: MacroStep
    let parameters: [MacroParameter]
    let allowRepeat: Bool
    let up: () -> Void
    let down: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Step", selection: $step.kind) {
                    ForEach(MacroStep.Kind.allCases.filter { allowRepeat || $0 != .repeatFor }) { Text($0.title).tag($0) }
                }
                Spacer()
                Button(action: up) { Image(systemName: "arrow.up") }.help("Move Up")
                Button(action: down) { Image(systemName: "arrow.down") }.help("Move Down")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.help("Delete Step")
            }
            PrimitiveStepFields(step: $step, parameters: parameters)
        }
        .onChange(of: step.kind) { _, kind in
            if kind == .repeatFor && step.children?.isEmpty != false { step.children = [.init(.moveMouse)] }
            if kind != .repeatFor { step.children = nil }
        }
    }
}

private struct RepeatStepFields: View {
    @Binding var step: MacroStep
    var body: some View {
        MacroNumberField(title: "Duration (minutes)", value: Binding(get: { step.jiggleDuration / 60 },
            set: { step.mouseDurationSeconds = min(1_440, max(1, $0)) * 60 }), range: 1...1_440)
        Picker("Interval", selection: Binding(get: { step.varyingInterval == true }, set: { step.varyingInterval = $0 })) {
            Text("Fixed").tag(false); Text("Range").tag(true)
        }.pickerStyle(.segmented)
        MacroNumberField(title: step.varyingInterval == true ? "Minimum interval (seconds)" : "Interval (seconds)",
            value: Binding(get: { step.jiggleInterval }, set: { step.mouseIntervalSeconds = min(3_600, max(1, $0)) }), range: 1...3_600)
        if step.varyingInterval == true {
            MacroNumberField(title: "Maximum interval (seconds)", value: Binding(get: { step.intervalMaximum },
                set: { step.mouseIntervalMaximumSeconds = min(3_600, max(1, $0)) }), range: 1...3_600)
        }
    }
}

private struct MacroEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedMacro
    @State private var error: String?
    let save: (SavedMacro) throws -> Void
    init(initial: SavedMacro, save: @escaping (SavedMacro) throws -> Void) {
        _draft = State(initialValue: initial.migratingLegacyMouse)
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
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
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
                            MacroStepRow(step: $step, parameters: draft.parameters, allowRepeat: true,
                                up: { move(step.id, -1) }, down: { move(step.id, 1) },
                                remove: { draft.steps.removeAll { $0.id == step.id } })
                            if step.kind == .repeatFor {
                                RepeatStepFields(step: $step)
                                Text("Repeated Steps").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(childSteps($step)) { $child in
                                    MacroStepRow(step: $child, parameters: draft.parameters, allowRepeat: false,
                                        up: { moveChild(child.id, -1, parent: $step) },
                                        down: { moveChild(child.id, 1, parent: $step) },
                                        remove: { step.children?.removeAll { $0.id == child.id } })
                                        .padding(.leading, 12)
                                    Divider()
                                }
                                Button { step.children = (step.children ?? []) + [.init(.moveMouse)] }
                                    label: { Label("Add Repeated Step", systemImage: "plus") }
                                    .disabled((step.children?.count ?? 0) >= 128)
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
            }.formStyle(.grouped)
        }
        .frame(width: 650, height: 680)
    }
    private func move(_ id: UUID, _ direction: Int) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }), draft.steps.indices.contains(index + direction) else { return }
        draft.steps.swapAt(index, index + direction)
    }
    private func childSteps(_ step: Binding<MacroStep>) -> Binding<[MacroStep]> {
        Binding(get: { step.wrappedValue.children ?? [] }, set: { step.wrappedValue.children = $0 })
    }
    private func moveChild(_ id: UUID, _ direction: Int, parent: Binding<MacroStep>) {
        var children = parent.wrappedValue.children ?? []
        guard let index = children.firstIndex(where: { $0.id == id }), children.indices.contains(index + direction) else { return }
        children.swapAt(index, index + direction); parent.wrappedValue.children = children
    }
}

private struct MacroRunReview: View {
    @Environment(\.dismiss) private var dismiss
    let macro: SavedMacro
    @ObservedObject var bluetooth: ClipboardBluetooth
    @State private var clipboard: String
    @State private var date = Date()
    @State private var values: [String: String] = [:]
    @State private var confirmed = false
    @State private var hideBeforeOutput = false
    @State private var destination: TransferDestination
    @State private var standalone: Bool
    @State private var storedName: String

    init(macro: SavedMacro, bluetooth: ClipboardBluetooth, destination: TransferDestination = .run) {
        self.macro = macro
        self.bluetooth = bluetooth
        _destination = State(initialValue: destination)
        _standalone = State(initialValue: macro.prefersStandalone)
        var name = macro.name
        while name.utf8.count > 79 { name.removeLast() }
        _storedName = State(initialValue: name)
        let needsClipboard = macro.flattenedSteps.contains { $0.kind == .template && $0.value.contains("{{clipboard}}") }
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
            Picker("Destination", selection: $destination) {
                ForEach(TransferDestination.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
                .onChange(of: destination) { _, _ in confirmed = false }
            if destination == .save { TextField("Name on Flipper", text: $storedName) }
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
            if destination == .save {
                Toggle("Store this plaintext snapshot on the Flipper SD card", isOn: $confirmed)
            } else {
                Toggle("The intended USB target and input field are focused", isOn: $confirmed)
                Toggle("Continue on Flipper if this Mac disconnects", isOn: $standalone)
                Toggle("Hide this app before output", isOn: $hideBeforeOutput)
            }
            HStack {
                Label(destination == .save ? "Clipboard, time and parameters are fixed at send time; no USB output now" :
                      standalone ? "Continues after Mac closes; physical Stop remains available" : "Line breaks send Enter; output cannot be undone", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    if case .success(let output) = compiled {
                        if destination == .save { bluetooth.saveToFlipper(output, id: macro.id, name: storedName) }
                        else { bluetooth.run(output, hideApp: hideBeforeOutput, standalone: standalone) }
                        dismiss()
                    }
                } label: { Label(destination.rawValue, systemImage: destination == .save ? "square.and.arrow.up" : "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
                    .accessibilityIdentifier("run-confirmed")
            }
        }.padding(24).frame(width: 650, height: 650)
    }
    private var canRun: Bool {
        guard confirmed, bluetooth.isReady, !bluetooth.isBusy, case .success = compiled else { return false }
        if destination == .save { return (try? SavedProgramRequest(id: macro.id, name: storedName).payload(jobID: 1)) != nil }
        return true
    }
}
