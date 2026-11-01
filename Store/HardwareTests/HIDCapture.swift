import AppKit
import Foundation

struct CaptureSnapshot: Encodable {
    let capturedAt: Date
    let text: String
    let firstField: String
    let secondField: String
    let changeCount: Int
}

final class CaptureDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    private let output: URL
    private let textView = NSTextView()
    private let first = NSTextField(string: "")
    private let second = NSTextField(string: "")
    private let status = NSTextField(labelWithString: "0 changes")
    private var window: NSWindow!
    private var changes = 0
    private var pendingSnapshot: DispatchWorkItem?

    init(output: URL) { self.output = output }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit USB Capture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "BT Paste - USB Hardware Capture"
        window.minSize = NSSize(width: 620, height: 420)
        window.isReleasedWhenClosed = false
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "USB Hardware Capture")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        root.addArrangedSubview(title)
        let toolbar = NSStackView(views: [
            NSButton(title: "Reset", target: self, action: #selector(reset)),
            NSButton(title: "Focus Text", target: self, action: #selector(focusText)),
            NSButton(title: "Focus First Field", target: self, action: #selector(focusFirst)),
            NSButton(title: "Snapshot", target: self, action: #selector(snapshotNow)),
        ])
        root.addArrangedSubview(toolbar)
        for (field, name) in [(first, "First Field"), (second, "Second Field")] {
            field.placeholderString = name
            field.setAccessibilityLabel(name)
            field.delegate = self
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            root.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        }
        first.nextKeyView = second
        second.nextKeyView = textView
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.setAccessibilityLabel("USB Capture Text")
        scroll.documentView = textView
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        root.addArrangedSubview(status)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusText()
        snapshotNow()
    }

    func textDidChange(_ notification: Notification) { changed() }
    func controlTextDidChange(_ obj: Notification) { changed() }
    private func changed() {
        changes += 1
        status.stringValue = "\(textView.string.utf8.count) text bytes; \(changes) changes"
        pendingSnapshot?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapshotNow() }
        pendingSnapshot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    @objc private func reset() {
        pendingSnapshot?.cancel()
        textView.string = ""
        first.stringValue = ""
        second.stringValue = ""
        changes = 0
        snapshotNow()
        focusText()
    }
    @objc private func focusText() { window.makeFirstResponder(textView) }
    @objc private func focusFirst() { window.makeFirstResponder(first) }
    @objc private func snapshotNow() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(CaptureSnapshot(capturedAt: Date(), text: textView.string,
                firstField: first.stringValue, secondField: second.stringValue, changeCount: changes))
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .atomic)
            status.stringValue = "\(textView.string.utf8.count) text bytes; \(changes) changes; snapshot saved"
        } catch { status.stringValue = "Snapshot failed: \(error.localizedDescription)" }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { pendingSnapshot?.cancel(); snapshotNow() }
}

let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let output = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("hardware/capture.json")
let app = NSApplication.shared
let delegate = CaptureDelegate(output: output)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
