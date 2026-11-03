import XCTest
import CoreBluetooth
@testable import BLEClipboardMac

final class TransferProtocolTests: XCTestCase {
    func id(_ value: UInt32 = 7) -> Data { var data = Data(); data.appendLE(value); return data }
    func reply(_ command: TransferCommand, _ payload: Data? = nil) -> TransferFrame {
        .init(command: command, payload: payload ?? id())
    }
    func ready(chunk: UInt16 = 512) -> TransferFrame {
        var data = Data(); data.appendLE(UInt32(65536)); data.appendLE(chunk); data.append(contentsOf: [28, 7, 31]); data.append(Data("Test Flipper".utf8))
        return reply(.ready, data)
    }
    func plan(_ text: String = "abc", layout: MacroLayout = .us, target: TargetSystem = .macOS) throws -> CompiledMacro {
        try MacroCompiler.compile(.init(name: "Test", target: target, layout: layout, steps: [.init(.text, text)]), context: .init(clipboard: "", date: Date()))
    }
    func ack(_ offset: Int) -> TransferFrame { var data = id(); data.appendLE(UInt32(offset)); return reply(.chunked, data) }
    func request(_ event: TransferSession.Event) throws -> TransferFrame {
        guard case .write(let data) = event else { throw MacroError.invalid("Expected write") }
        var reader = BinaryReader(data)
        XCTAssertEqual(try reader.byte(), 4)
        let command = try XCTUnwrap(TransferCommand(rawValue: reader.byte()))
        let count = Int(try reader.u16())
        let payload = try reader.data(count)
        XCTAssertEqual(reader.remaining, 0)
        return .init(command: command, payload: payload)
    }

    func testPermissionDiagnosticsAndCRC() throws {
        XCTAssertTrue(ClipboardBluetooth.unavailableStatus(for: .unknown).contains("authorization"))
        XCTAssertTrue(ClipboardBluetooth.unavailableStatus(for: .unauthorized).contains("Allow"))
        XCTAssertEqual(TransferProtocol.crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(TransferProtocol.crc32(Data()), 0)
    }

    func testFragmentedRepeatedFramesAndMalformedHeaders() throws {
        var decoder = TransferFrameDecoder()
        let bytes = ready().encoded()
        XCTAssertEqual(try decoder.append(bytes.prefix(3)), [])
        XCTAssertEqual(try decoder.append(bytes.dropFirst(3)), [ready()])
        XCTAssertEqual(try decoder.append(bytes + bytes), [ready(), ready()])
        XCTAssertThrowsError(try decoder.append(Data([2])))
        XCTAssertThrowsError(try decoder.append(Data([4, 0x81, 0xFF, 0xFF])))
        XCTAssertThrowsError(try decoder.append(Data([4, 0x8E, 0, 0])))
        XCTAssertEqual(try decoder.append(bytes), [ready()])
    }

    func testExecutionRequiresCompleteAcknowledgedUploadAndVerification() throws {
        var session = TransferSession()
        let macro = try plan()
        XCTAssertEqual(try session.receive(ready()), [.ready(65536, "Test Flipper")])
        let begin = try request(XCTUnwrap(session.begin(macro, jobID: 7).first))
        XCTAssertEqual(begin.command, .begin)
        XCTAssertEqual(begin.payload.count, 15)
        XCTAssertEqual(try session.receive(reply(.verified)), [])
        let chunk = try request(XCTUnwrap(session.receive(reply(.begun)).first))
        XCTAssertEqual(chunk.command, .chunk)
        XCTAssertEqual(chunk.payload.dropFirst(8), macro.program)
        XCTAssertEqual(try session.receive(reply(.verified)), [])
        XCTAssertThrowsError(try session.begin(macro, jobID: 8))
        let commitEvents = try session.receive(ack(macro.bytes))
        XCTAssertEqual(try request(XCTUnwrap(commitEvents.last)).command, .commit)
        XCTAssertEqual(try request(XCTUnwrap(session.receive(reply(.verified)).first)).command, .execute)
        XCTAssertEqual(try session.receive(reply(.waitingUSB)), [.waitingUSB])
        XCTAssertEqual(try session.receive(reply(.started)), [.accepted])
        XCTAssertEqual(try session.receive(reply(.done, id() + Data([0]))), [.done(cancelled: false)])
        XCTAssertEqual(session.stage, .idle)
        XCTAssertEqual(try session.receive(reply(.verified)), [])
    }

    func testCancelDuringBeginUploadAndCommitNeverExecutes() throws {
        for phase in 0...2 {
            var session = TransferSession()
            let macro = try plan()
            _ = try session.receive(ready())
            _ = try session.begin(macro, jobID: 7)
            if phase >= 1 { _ = try session.receive(reply(.begun)) }
            if phase >= 2 { _ = try session.receive(ack(macro.bytes)) }
            XCTAssertEqual(session.cancel(), [])
            let response: TransferFrame = phase == 0 ? reply(.begun) : phase == 1 ? ack(macro.bytes) : reply(.verified)
            let events = try session.receive(response)
            XCTAssertEqual(try request(XCTUnwrap(events.last)).command, .cancel)
            XCTAssertEqual(session.stage, .cancelling)
            XCTAssertEqual(try session.receive(reply(.done, id() + Data([1]))), [.done(cancelled: true)])
            XCTAssertEqual(session.capacity, 65536)
            XCTAssertEqual(session.stage, .idle)
        }
    }

    func testCancelDuringExecutionKeepsTheSessionReady() throws {
        var session = TransferSession()
        let macro = try plan()
        _ = try session.receive(ready()); _ = try session.begin(macro, jobID: 7)
        _ = try session.receive(reply(.begun)); _ = try session.receive(ack(macro.bytes))
        _ = try session.receive(reply(.verified)); _ = try session.receive(reply(.started))
        XCTAssertEqual(try request(XCTUnwrap(session.cancel().first)).command, .cancel)
        XCTAssertEqual(try session.receive(reply(.started)), [])
        XCTAssertEqual(try session.receive(reply(.done, id() + Data([1]))), [.done(cancelled: true)])
        XCTAssertNoThrow(try session.begin(macro, jobID: 8))
        XCTAssertEqual(try session.receive(reply(.done, id(7) + Data([0]))), [])
    }

    func testChunksAreBoundedAndDuplicateOrStaleAcknowledgementsDoNotReplay() throws {
        var session = TransferSession()
        let macro = try plan(String(repeating: "x", count: 1000))
        _ = try session.receive(ready(chunk: 32)); _ = try session.begin(macro, jobID: 7)
        var events = try session.receive(reply(.begun))
        var offset = 0
        while session.stage == .receiving {
            let chunk = try request(XCTUnwrap(events.last))
            XCTAssertEqual(chunk.command, .chunk)
            XCTAssertLessThanOrEqual(chunk.payload.count, 40)
            XCTAssertEqual(try session.receive(ack(offset)), [])
            offset += chunk.payload.count - 8
            events = try session.receive(ack(offset))
        }
        XCTAssertEqual(offset, macro.bytes)
        XCTAssertEqual(try request(XCTUnwrap(events.last)).command, .commit)
        XCTAssertEqual(try session.receive(reply(.error, id(9) + Data([2]) + Data("stale".utf8))), [])
    }

    func testWrongOffsetsUnsupportedCapabilitiesAndInvalidProgressAreRejected() throws {
        var session = TransferSession()
        XCTAssertThrowsError(try session.receive(reply(.ready, Data(repeating: 0, count: 9))))
        _ = try session.receive(ready())
        let macro = try plan()
        _ = try session.begin(macro, jobID: 7); _ = try session.receive(reply(.begun))
        XCTAssertThrowsError(try session.receive(ack(macro.bytes + 1)))
        _ = try session.receive(ack(macro.bytes)); _ = try session.receive(reply(.verified))
        var progress = id(); progress.appendLE(UInt32(macro.bytes + 1)); progress.appendLE(UInt32(macro.bytes))
        XCTAssertThrowsError(try session.receive(reply(.progress, progress)))
        XCTAssertEqual(try session.receive(reply(.error, id() + Data([6]) + Data("Unsupported text".utf8))), [.failed("Unsupported text")])
        XCTAssertEqual(session.stage, .idle)
    }

    func testAll28LayoutsAndThreeTargetsHaveStableBinaryIDs() throws {
        XCTAssertEqual(KeyboardLayout.allCases.count, 28)
        for layout in KeyboardLayout.allCases {
            XCTAssertEqual(KeyboardLayout(wireID: layout.wireID), layout)
            XCTAssertEqual(try JSONDecoder().decode(KeyboardLayout.self, from: JSONEncoder().encode(layout)), layout)
            for target in TargetSystem.allCases {
                var session = TransferSession()
                _ = try session.receive(ready())
                let frame = try request(XCTUnwrap(session.begin(plan("abc", layout: layout, target: target), jobID: 7).first))
                XCTAssertEqual(frame.payload[4], layout.wireID)
                XCTAssertEqual(frame.payload[5], target.wireID)
            }
        }
        XCTAssertNil(KeyboardLayout(wireID: 28))
    }

    func testProgramCodecLimitsAndInvalidRecords() throws {
        let maximum = try plan(String(repeating: "x", count: 65525))
        XCTAssertEqual(maximum.bytes, 65536)
        XCTAssertThrowsError(try plan(String(repeating: "x", count: 65526)))
        for size in 0..<14 { XCTAssertThrowsError(try MacroProgram.decode(try plan().program.prefix(size))) }
        XCTAssertThrowsError(try MacroProgram.decode(maximum.program + Data([0])))
        XCTAssertThrowsError(try MacroProgram.encode([.key(modifiers: 0x80, code: 97)]))
        XCTAssertThrowsError(try MacroProgram.encode([.key(modifiers: 0, code: 0xFFFF)]))
        XCTAssertThrowsError(try MacroProgram.encode([.delay(30_001), .text("x")]))
        XCTAssertThrowsError(try MacroProgram.encode([.delay(1)]))
        XCTAssertThrowsError(try MacroProgram.encode(Array(repeating: .text("x"), count: 129)))
    }
}

final class ProgramFixtureTests: XCTestCase {
    func testExportIndependentFirmwareContractFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["CLIPBOARD_FIXTURE_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let letters = "\u{00E7}\u{00C7}\u{011F}\u{011E}\u{0131}\u{0130}\u{00F6}\u{00D6}\u{015F}\u{015E}\u{00FC}\u{00DC}s\u{0327}I\u{0307}"
        var jiggle = SavedMacro.mouseJiggler()
        jiggle.steps[0].mouseDurationSeconds = 2
        jiggle.steps[0].mouseIntervalSeconds = 1
        jiggle.steps[0].mouseIntervalMaximumSeconds = 1
        let macros: [(String, SavedMacro)] = [
            ("literal", .init(name: "Literal", steps: [.init(.text, "Literal [ENTER] [GUI+r] [] {{clipboard}}") ])),
            ("turkish", .init(name: "Turkish", layout: .turkishQ, steps: [.init(.text, letters)])),
            ("large", .init(name: "Maximum", steps: [.init(.text, String(repeating: "x", count: 65525))])),
            ("macro", .init(name: "Structured", steps: [.init(.text, "first"), .init(.chord, "PRIMARY+A"), .init(.chord, "TAB"), .init(.delay, milliseconds: 25), .init(.text, "second")])),
            ("jiggle", jiggle),
            ("saved", .init(name: "Saved Snapshot", steps: [.init(.text, "Persisted clipboard [ENTER]")])),
        ]
        for (name, macro) in macros {
            let compiled = try MacroCompiler.compile(macro, context: .init(clipboard: "", date: Date(timeIntervalSince1970: 0)))
            try compiled.program.write(to: directory.appendingPathComponent("\(name).bcm"))
            let helper = TransferProtocolTests()
            var session = TransferSession()
            _ = try session.receive(helper.ready())
            var events = try session.begin(compiled, jobID: 7,
                saved: name == "saved" ? .init(id: macro.id, name: macro.name) : nil, standalone: name == "jiggle")
            var wire = TransferProtocol.hello
            while let event = events.last {
                let frame = try helper.request(event)
                wire.append(frame.encoded())
                switch frame.command {
                case .begin: events = try session.receive(helper.reply(.begun))
                case .chunk:
                    var reader = BinaryReader(frame.payload)
                    _ = try reader.u32(); let offset = try reader.u32()
                    events = try session.receive(helper.ack(Int(offset) + reader.remaining))
                case .commit: events = try session.receive(helper.reply(.verified))
                case .execute, .save: events = []
                default: XCTFail("Unexpected fixture command"); events = []
                }
            }
            try wire.write(to: directory.appendingPathComponent("\(name).wire"))
        }
    }
}
