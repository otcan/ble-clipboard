import XCTest
@testable import BLEClipboardMac

final class MouseActionTests: XCTestCase {
    let context = MacroRunContext(clipboard: "Snapshot [ENTER]", date: Date(timeIntervalSince1970: 0))

    func testMoveMouseAndRepeatAreActionsAndJiggleIsOnlyAPreset() throws {
        XCTAssertFalse(MacroStep.Kind.allCases.contains(.mouseJiggle))
        XCTAssertTrue(MacroStep.Kind.allCases.contains(.moveMouse))
        XCTAssertTrue(MacroStep.Kind.allCases.contains(.repeatFor))
        let macro = SavedMacro.mouseJiggler()
        XCTAssertEqual(macro.steps.first?.kind, .repeatFor)
        XCTAssertEqual(macro.steps.first?.children?.first?.kind, .moveMouse)
        XCTAssertTrue(macro.prefersStandalone)
        let compiled = try MacroCompiler.compile(macro, context: context)
        XCTAssertEqual(compiled.bytes, 30)
        XCTAssertEqual(try MacroProgram.decode(compiled.program), compiled.operations)
        XCTAssertTrue(compiled.preview.joined().contains("-2...2"))
        XCTAssertTrue(compiled.preview.joined().contains("45...95"))
    }

    func testFixedAndRangedMoveCodecAndBoundaryValidation() throws {
        for op: MacroOperation in [
            .moveMouse(xMin: -127, xMax: 127, yMin: -127, yMax: 127),
            .moveMouse(xMin: 1, xMax: 1, yMin: 0, yMax: 0),
        ] {
            let data = try MacroProgram.encode([op])
            XCTAssertEqual(data.count, 11)
            XCTAssertEqual(try MacroProgram.decode(data), [op])
        }
        for op: MacroOperation in [
            .moveMouse(xMin: -128, xMax: 1, yMin: 0, yMax: 0),
            .moveMouse(xMin: 2, xMax: 1, yMin: 0, yMax: 0),
            .moveMouse(xMin: 0, xMax: 0, yMin: 0, yMax: 0),
        ] { XCTAssertThrowsError(try MacroProgram.encode([op])) }
    }

    func testRepeatValidatesEveryBodyOperationAndRejectsNesting() throws {
        let move = MacroOperation.moveMouse(xMin: 1, xMax: 2, yMin: -1, yMax: 1)
        let valid = MacroOperation.repeatFor(duration: 8_000, intervalMin: 1_000, intervalMax: 2_000, body: [move, .delay(50)])
        let bytes = try MacroProgram.encode([valid, .text("after")])
        XCTAssertEqual(try MacroProgram.decode(bytes), [valid, .text("after")])
        for op: MacroOperation in [
            .repeatFor(duration: 8_000, intervalMin: 2_000, intervalMax: 1_000, body: [move]),
            .repeatFor(duration: 8_000, intervalMin: 1_000, intervalMax: 2_000, body: [.delay(1)]),
            .repeatFor(duration: 8_000, intervalMin: 1_000, intervalMax: 2_000, body: [valid]),
            .repeatFor(duration: 8_000, intervalMin: 1_000, intervalMax: 2_000, body: [.mouseJiggle(duration: 1_000, interval: 1_000)]),
        ] { XCTAssertThrowsError(try MacroProgram.encode([op])) }
        for size in 0..<bytes.count {
            XCTAssertThrowsError(try MacroProgram.decode(bytes.prefix(size)))
        }
        var wrongLength = bytes
        wrongLength[21] = 0xFF
        XCTAssertThrowsError(try MacroProgram.decode(wrongLength))
    }

    @MainActor func testLegacyJSONMigratesWithoutChangingIDsDurationOrLayout() throws {
        let old = SavedMacro(name: "Existing", target: .linux, layout: .german, steps: [.init(.mouseJiggle)])
        let data = try JSONEncoder().encode(MacroDocument(schemaVersion: 2, macros: [old]))
        let result = try XCTUnwrap(MacroLibrary.decode(data).first)
        XCTAssertEqual(result.id, old.id)
        XCTAssertEqual(result.steps.first?.id, old.steps.first?.id)
        XCTAssertEqual(result.layout, .german)
        XCTAssertEqual(result.target, .linux)
        XCTAssertEqual(result.steps.first?.jiggleDuration, 28_800)
        XCTAssertEqual(result.steps.first?.jiggleInterval, 60)
        XCTAssertEqual(result.steps.first?.children?.map(\.kind), [.moveMouse, .delay, .moveMouse])
        XCTAssertEqual(MacroDocument(macros: [result]).schemaVersion, 3)
        XCTAssertNoThrow(try MacroCompiler.compile(result, context: context))
    }

    func testRepeatedTemplatesAreSnapshotsAndDefinitionLimitsStillApply() throws {
        var step = MacroStep(.repeatFor)
        step.children = [.init(.template, "{{clipboard}}")]
        let macro = SavedMacro(name: "Repeated", steps: [step])
        let compiled = try MacroCompiler.compile(macro, context: context)
        XCTAssertTrue(macro.flattenedSteps.contains { $0.kind == .template })
        XCTAssertEqual(compiled.operations, [.repeatFor(duration: 28_800_000, intervalMin: 60_000,
            intervalMax: 60_000, body: [.text("Snapshot [ENTER]")])])
        step.children = [.init(.repeatFor)]
        XCTAssertThrowsError(try MacroCompiler.validate(.init(name: "Nested", steps: [step])))
        step.children = Array(repeating: .init(.moveMouse), count: 2)
        XCTAssertThrowsError(try MacroCompiler.validate(.init(name: "Duplicate", steps: [step])))
        step.children = [.init(.moveMouse)]
        step.mouseIntervalMaximumSeconds = 1; step.varyingInterval = true
        XCTAssertThrowsError(try MacroCompiler.validate(.init(name: "Inverted", steps: [step])))
    }
}
