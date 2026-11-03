import XCTest
@testable import BLEClipboardMac

final class MacroTests: XCTestCase {
    let context = MacroRunContext(clipboard: "[ENTER] {{timestamp}} []", date: Date(timeIntervalSince1970: 0))

    func testEveryStarterCompilesWithoutSubmittingForms() throws {
        for macro in SavedMacro.starters() {
            let result = try MacroCompiler.compile(macro, context: .init(clipboard: "hello", date: context.date,
                parameters: ["first": "Ada", "second": "Lovelace"]))
            XCTAssertFalse(result.program.isEmpty)
            XCTAssertEqual(try MacroProgram.decode(result.program), result.operations)
        }
        XCTAssertFalse(try MacroCompiler.compile(SavedMacro.starters()[4], context: .init(clipboard: "", date: context.date,
            parameters: ["first": "one", "second": "two"])).operations.contains(.key(modifiers: 0, code: 0x100)))
    }

    func testLiteralClipboardAndParametersNeverBecomeKeyCommands() throws {
        let result = try MacroCompiler.compile(SavedMacro.starters()[0], context: context)
        XCTAssertEqual(result.operations, [.text("[ENTER] {{timestamp}} []")])
        let macro = SavedMacro(name: "Prompt", steps: [.init(.template, "{{value}}")], parameters: [.init(id: "value", label: "Value")])
        XCTAssertEqual(try MacroCompiler.compile(macro, context: .init(clipboard: "", date: context.date,
            parameters: ["value": "[WIN+r]{{clipboard}}"])).operations, [.text("[WIN+r]{{clipboard}}")])
    }

    func testTextStepsDoNotInterpretTemplates() throws {
        let macro = SavedMacro(name: "Literal", steps: [.init(.text, "{{clipboard}}")])
        XCTAssertEqual(try MacroCompiler.compile(macro, context: context).operations, [.text("{{clipboard}}")])
    }

    func testRepeatedLargeParametersAreBoundedBeforeExpansion() throws {
        let macro = SavedMacro(name: "Bounded", steps: [.init(.template, String(repeating: "{{clipboard}}", count: 1000))])
        XCTAssertThrowsError(try MacroCompiler.compile(macro, context: .init(clipboard: String(repeating: "x", count: 65_536), date: context.date)))
    }

    @MainActor func testUnsupportedSchemaDuplicatesAndOversizedImportAreRejected() throws {
        let macro = SavedMacro.starters()[0]
        let encoder = JSONEncoder()
        XCTAssertThrowsError(try MacroLibrary.decode(encoder.encode(MacroDocument(schemaVersion: 4, macros: [macro]))))
        XCTAssertThrowsError(try MacroLibrary.decode(encoder.encode(MacroDocument(macros: [macro, macro]))))
        XCTAssertThrowsError(try MacroLibrary.decode(Data(repeating: 32, count: 2_000_001)))
    }

    func testTargetSpecificShortcutAndTimestamp() throws {
        var macro = SavedMacro.starters()[3]
        XCTAssertEqual(try MacroCompiler.compile(macro, context: context).operations.first, .key(modifiers: 8, code: 97))
        macro.target = .windows
        XCTAssertEqual(try MacroCompiler.compile(macro, context: context).operations.first, .key(modifiers: 1, code: 97))
        XCTAssertEqual(try MacroCompiler.compile(SavedMacro.starters()[2], context: context).operations, [.text("1970-01-01T00:00:00Z")])
    }

    func testCompiledTurkishPlanRetainsItsTargetAndLiteralText() throws {
        for target in TargetSystem.allCases {
            let macro = SavedMacro(name: "Punctuation", target: target, layout: .turkishQ,
                                   steps: [.init(.text, "\"<>|^`a~[ENTER]")])
            let compiled = try MacroCompiler.compile(macro, context: context)
            XCTAssertEqual(compiled.target, target)
            XCTAssertEqual(compiled.operations, [.text("\"<>|^`a~[ENTER]")])
            XCTAssertEqual(compiled.layout, .turkishQ)
        }
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

    func testTurkishLettersUseLiteralUTF8AndNormalizeDecomposedInput() throws {
        let letters = "\u{00E7}\u{00C7}\u{011F}\u{011E}\u{0131}\u{0130}\u{00F6}\u{00D6}\u{015F}\u{015E}\u{00FC}\u{00DC}"
        var macro = SavedMacro(name: "Turkish", layout: .turkishQ, steps: [.init(.text, letters)])
        let compiled = try MacroCompiler.compile(macro, context: context)
        XCTAssertEqual(compiled.operations, [.text(letters)])
        XCTAssertEqual(try MacroProgram.decode(compiled.program), [.text(letters)])
        macro.steps = [.init(.template, "{{clipboard}} {{value}}")]
        macro.parameters = [.init(id: "value", label: "Value")]
        let result = try MacroCompiler.compile(macro, context: .init(clipboard: "s\u{0327}", date: context.date,
            parameters: ["value": "I\u{0307}[TR:011F][WIN+r]"]))
        XCTAssertEqual(result.operations, [.text("\u{015F} \u{0130}[TR:011F][WIN+r]")])
        macro.steps = [.init(.text, "[TR:011F]")]
        XCTAssertEqual(try MacroCompiler.compile(macro, context: context).operations, [.text("[TR:011F]")])
        for layout in MacroLayout.allCases where layout != .turkishQ {
            macro.layout = layout
            macro.steps = [.init(.text, letters)]
            XCTAssertThrowsError(try MacroCompiler.compile(macro, context: context))
        }
    }

    func testTurkishWireExpansionUsesTheConnectedCapacity() throws {
        let macro = SavedMacro(name: "Turkish", layout: .turkishQ, steps: [.init(.text, "\u{011F}")])
        XCTAssertThrowsError(try MacroCompiler.compile(macro, context: context, limit: 12))
        XCTAssertEqual(try MacroCompiler.compile(macro, context: context, limit: 13).bytes, 13)
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
