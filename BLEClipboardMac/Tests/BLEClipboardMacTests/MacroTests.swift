import XCTest
@testable import BLEClipboardMac

final class MacroTests: XCTestCase {
    let context = MacroRunContext(clipboard: "[ENTER] {{timestamp}} []", date: Date(timeIntervalSince1970: 0))

    func testEveryStarterCompilesWithoutSubmittingForms() throws {
        for macro in SavedMacro.starters() {
            let result = try MacroCompiler.compile(macro, context: .init(clipboard: "hello", date: context.date,
                parameters: ["first": "Ada", "second": "Lovelace"]))
            XCTAssertFalse(result.script.isEmpty)
        }
        XCTAssertFalse(try MacroCompiler.compile(SavedMacro.starters()[4], context: .init(clipboard: "", date: context.date,
            parameters: ["first": "one", "second": "two"])).script.contains("[ENTER]"))
    }

    func testLiteralClipboardAndParameterInjectionAreEscaped() throws {
        let result = try MacroCompiler.compile(SavedMacro.starters()[0], context: context)
        XCTAssertEqual(result.script, "[]ENTER] {{timestamp}} []]")
        let macro = SavedMacro(name: "Prompt", steps: [.init(.template, "{{value}}")], parameters: [.init(id: "value", label: "Value")])
        XCTAssertEqual(try MacroCompiler.compile(macro, context: .init(clipboard: "", date: context.date,
            parameters: ["value": "[WIN+r]{{clipboard}}"])).script, "[]WIN+r]{{clipboard}}")
    }

    func testTextStepsDoNotInterpretTemplates() throws {
        let macro = SavedMacro(name: "Literal", steps: [.init(.text, "{{clipboard}}")])
        XCTAssertEqual(try MacroCompiler.compile(macro, context: context).script, "{{clipboard}}")
    }

    func testRepeatedLargeParametersAreBoundedBeforeExpansion() throws {
        let macro = SavedMacro(name: "Bounded", steps: [.init(.template, String(repeating: "{{clipboard}}", count: 1000))])
        XCTAssertThrowsError(try MacroCompiler.compile(macro, context: .init(clipboard: String(repeating: "x", count: 65_536), date: context.date)))
    }

    @MainActor func testUnsupportedSchemaDuplicatesAndOversizedImportAreRejected() throws {
        let macro = SavedMacro.starters()[0]
        let encoder = JSONEncoder()
        XCTAssertThrowsError(try MacroLibrary.decode(encoder.encode(MacroDocument(schemaVersion: 2, macros: [macro]))))
        XCTAssertThrowsError(try MacroLibrary.decode(encoder.encode(MacroDocument(macros: [macro, macro]))))
        XCTAssertThrowsError(try MacroLibrary.decode(Data(repeating: 32, count: 2_000_001)))
    }

    func testTargetSpecificShortcutAndTimestamp() throws {
        var macro = SavedMacro.starters()[3]
        XCTAssertTrue(try MacroCompiler.compile(macro, context: context).script.hasPrefix("[WIN+a]"))
        macro.target = .windows
        XCTAssertTrue(try MacroCompiler.compile(macro, context: context).script.hasPrefix("[CTRL+a]"))
        XCTAssertEqual(try MacroCompiler.compile(SavedMacro.starters()[2], context: context).script, "1970-01-01T00:00:00Z")
    }

    func testInvalidDefinitionsAndExpandedCapacity() throws {
        var macro = SavedMacro(name: "Invalid", steps: [.init(.template, "{{missing}}")])
        XCTAssertThrowsError(try MacroCompiler.validate(macro))
        macro.steps = [.init(.template, "{{broken")]
        XCTAssertThrowsError(try MacroCompiler.validate(macro))
        macro.steps = [.init(.chord, "CTRL+[ENTER]")]
        XCTAssertThrowsError(try MacroCompiler.validate(macro))
        macro.steps = [.init(.delay, milliseconds: 30_001)]
        XCTAssertThrowsError(try MacroCompiler.validate(macro))
        macro.steps = [.init(.text, "abc")]
        XCTAssertThrowsError(try MacroCompiler.compile(macro, context: context, limit: 2))
        macro.steps = [.init(.text, "\u{1B}")]
        XCTAssertThrowsError(try MacroCompiler.validate(macro))
    }

    @MainActor func testPersistenceImportAndRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let library = MacroLibrary(url: url)
        XCTAssertEqual(library.macros.count, 5)
        var macro = library.macros[0]
        macro.name = "Updated"
        try library.save(macro)
        XCTAssertEqual(MacroLibrary(url: url).macros[0].name, "Updated")
        let export = try library.exportData([macro.id])
        XCTAssertEqual(try MacroLibrary.decode(export).count, 1)
        _ = try library.importData(export)
        XCTAssertEqual(library.macros.count, 6)
        XCTAssertEqual(Set(library.macros.map(\.id)).count, 6)
        try Data("corrupt".utf8).write(to: url)
        let broken = MacroLibrary(url: url)
        XCTAssertNotNil(broken.error)
        XCTAssertThrowsError(try broken.save(macro))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "corrupt")
        try broken.recoverBackup()
        XCTAssertEqual(broken.macros.count, 5)
    }
}
