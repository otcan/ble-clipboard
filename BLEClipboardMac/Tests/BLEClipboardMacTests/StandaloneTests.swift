import XCTest
@testable import BLEClipboardMac

final class StandaloneTests: XCTestCase {
    let helper = TransferProtocolTests()

    func testMouseJiggleHasABoundedCompactEncoding() throws {
        let compiled = try MacroCompiler.compile(.mouseJiggler(), context: .init(clipboard: "", date: Date()))
        XCTAssertEqual(compiled.bytes, 30)
        XCTAssertEqual(compiled.operations, [.repeatFor(duration: 28_800_000, intervalMin: 45_000, intervalMax: 95_000,
            body: [.moveMouse(xMin: -2, xMax: 2, yMin: -2, yMax: 2)])])
        XCTAssertTrue(compiled.hasMouse)
        XCTAssertEqual(try MacroProgram.decode(compiled.program), compiled.operations)
        for operation: MacroOperation in [
            .mouseJiggle(duration: 0, interval: 1_000), .mouseJiggle(duration: 86_400_001, interval: 1_000),
            .mouseJiggle(duration: 1_000, interval: 999), .mouseJiggle(duration: 1_000, interval: 3_600_001),
        ] { XCTAssertThrowsError(try MacroProgram.encode([operation])) }
        XCTAssertThrowsError(try MacroProgram.encode(Array(repeating: .mouseJiggle(duration: 86_400_000, interval: 1_000), count: 2)))
        var macro = SavedMacro.mouseJiggler()
        macro.steps[0].mouseDurationSeconds = Int.max
        XCTAssertThrowsError(try MacroCompiler.compile(macro, context: .init(clipboard: "", date: Date())))
    }

    @MainActor func testOldJSONAndNewMouseJSONRoundTrip() throws {
        let old = SavedMacro(name: "Old", steps: [.init(.text, "literal")])
        let encoder = JSONEncoder()
        let bytes = try encoder.encode(MacroDocument(macros: [old]))
        XCTAssertEqual(try JSONDecoder().decode(MacroDocument.self, from: bytes).schemaVersion, 1)
        XCTAssertEqual(try MacroLibrary.decode(bytes), [old])
        let new = SavedMacro.mouseJiggler()
        let document = MacroDocument(macros: [old, new])
        XCTAssertEqual(document.schemaVersion, 3)
        XCTAssertEqual(try MacroLibrary.decode(encoder.encode(document)), [old, new])
    }

    func testStandaloneIsExplicitAndSaveNeverSendsExecute() throws {
        let macro = try helper.plan()
        var live = TransferSession()
        _ = try live.receive(helper.ready())
        XCTAssertEqual(try helper.request(XCTUnwrap(live.begin(macro, jobID: 7).first)).payload.last, 0)
        var autonomous = TransferSession()
        _ = try autonomous.receive(helper.ready())
        XCTAssertEqual(try helper.request(XCTUnwrap(autonomous.begin(macro, jobID: 7, standalone: true).first)).payload.last, 1)
        XCTAssertTrue(autonomous.autonomous)
        var saving = TransferSession()
        _ = try saving.receive(helper.ready())
        let metadata = SavedProgramRequest(id: UUID(), name: "Saved clipboard")
        XCTAssertEqual(try helper.request(XCTUnwrap(saving.begin(macro, jobID: 7, saved: metadata).first)).payload.last, 2)
        _ = try saving.receive(helper.reply(.begun)); _ = try saving.receive(helper.ack(macro.bytes))
        let saved = try helper.request(XCTUnwrap(saving.receive(helper.reply(.verified)).first))
        XCTAssertEqual(saved.command, .save)
        XCTAssertEqual(saved.payload, try metadata.payload(jobID: 7))
        XCTAssertEqual(saving.stage, .saving)
        XCTAssertEqual(saving.cancel(), []) // Atomic save may finish even if Stop was requested late.
        XCTAssertEqual(try saving.receive(helper.reply(.saved)), [.saved])
        XCTAssertEqual(saving.stage, .idle)
        XCTAssertEqual(try saving.receive(helper.reply(.started)), [])
    }

    func testReconnectAttachesOnlyToAnExplicitStandaloneJobAndAllowsStop() throws {
        var session = TransferSession()
        _ = try session.receive(helper.ready())
        var active = helper.id(42)
        active.appendLE(UInt32(15)); active.appendLE(UInt32(3_600_000)); active.appendLE(UInt32(25_200_000)); active.append(1)
        XCTAssertEqual(try session.receive(helper.reply(.active, active)), [.resumed, .timer(elapsed: 3_600, remaining: 25_200)])
        XCTAssertTrue(session.autonomous)
        XCTAssertEqual(session.jobID, 42)
        let cancel = try helper.request(XCTUnwrap(session.cancel().first))
        XCTAssertEqual(cancel.command, .cancel)
        XCTAssertEqual(cancel.payload, helper.id(42))
        XCTAssertEqual(try session.receive(helper.reply(.done, helper.id(42) + Data([1]))), [.done(cancelled: true)])
        XCTAssertEqual(session.stage, .idle)
        active[16] = 0
        XCTAssertThrowsError(try session.receive(helper.reply(.active, active)))
    }

    func testSaveErrorsPreserveTheirContextBeforeResettingTheJob() throws {
        let macro = try helper.plan()
        let message = "Save failed; check SD space or the 20-slot limit"
        for phase in 0...3 {
            var session = TransferSession()
            _ = try session.receive(helper.ready())
            _ = try session.begin(macro, jobID: 7, saved: .init(id: UUID(), name: "Snapshot"))
            if phase >= 1 { _ = try session.receive(helper.reply(.begun)) }
            if phase >= 2 { _ = try session.receive(helper.ack(macro.bytes)) }
            if phase >= 3 { _ = try session.receive(helper.reply(.verified)) }
            XCTAssertTrue(session.isSaving)
            let events = try session.receive(helper.reply(.error, helper.id() + Data([4]) + Data(message.utf8)))
            XCTAssertEqual(events, [.failed(message, saving: true)])
            XCTAssertEqual(session.stage, .idle)
            XCTAssertFalse(session.isSaving)
            XCTAssertNoThrow(try session.begin(macro, jobID: 8))
        }
    }

    func testSaveRejectionsDoNotClaimThatUSBOutputRan() {
        XCTAssertEqual(ClipboardBluetooth.rejectionStatus("SD failure", saving: true),
                       "Flipper could not save the snapshot: SD failure. No USB output was started.")
        XCTAssertEqual(ClipboardBluetooth.rejectionStatus("USB failure", saving: false),
                       "Flipper rejected the run: USB failure. Check the target before retrying.")
    }

    func testLabelsAndIdentifiersAreValidatedBeforeAnyTransfer() throws {
        for name in ["", "\n", "bad\tname", String(repeating: "x", count: 80)] {
            var session = TransferSession(); _ = try session.receive(helper.ready())
            XCTAssertThrowsError(try session.begin(helper.plan(), saved: .init(id: UUID(), name: name)))
            XCTAssertEqual(session.stage, .idle)
        }
        XCTAssertThrowsError(try SavedProgramRequest(id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000")), name: "Empty ID").payload(jobID: 7))
        XCTAssertNoThrow(try SavedProgramRequest(id: UUID(), name: "Turkish \u{015F}\u{011F}").payload(jobID: 7))
    }

    func testClipboardSnapshotIsResolvedBeforeSaving() throws {
        let definition = SavedMacro(name: "Clipboard", steps: [.init(.template, "{{clipboard}}")])
        let first = try MacroCompiler.compile(definition, context: .init(clipboard: "First [ENTER]", date: Date()))
        _ = try MacroCompiler.compile(definition, context: .init(clipboard: "Second", date: Date()))
        XCTAssertEqual(try MacroProgram.decode(first.program), [.text("First [ENTER]")])
    }
}
