import Foundation
import XCTest
@testable import BLEClipboardMac

final class InteropTests: XCTestCase {
    func testSharedLibraryRoundTripAndCompilerBytes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = root.appendingPathComponent("scripts/tests/fixtures")
        let data = try Data(contentsOf: fixtures.appendingPathComponent("library-interop.json"))
        var document = try JSONDecoder().decode(MacroDocument.self, from: data)
        document.macros = document.macros.map(\.migratingLegacyMouse)
        XCTAssertEqual(try JSONDecoder().decode(MacroDocument.self, from: JSONEncoder().encode(document)), document)
        XCTAssertEqual(document.macros[0].updatedAt.timeIntervalSinceReferenceDate, 721692800)
        for (index, macro) in document.macros.enumerated() {
            let output = try MacroCompiler.compile(macro, context: .init(clipboard: "{{name}}", date: Date(timeIntervalSince1970: 1700000000), parameters: ["name": "Sam"]), timing: .variable)
            let expected = try String(contentsOf: fixtures.appendingPathComponent("interop-\(index).hex"), encoding: .ascii).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(output.program.map { String(format: "%02x", $0) }.joined(), expected)
            XCTAssertEqual(try MacroProgram.encode(MacroProgram.decode(output.program)), output.program)
            if let path = ProcessInfo.processInfo.environment["CLIPBOARD_FIXTURE_DIR"] {
                let directory = URL(fileURLWithPath: path).appendingPathComponent("swift")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var header = Data(); header.appendLE(UInt32(7)); header.append(macro.layout.wireID); header.append(macro.target.wireID)
                header.appendLE(UInt32(output.program.count)); header.appendLE(TransferProtocol.crc32(output.program)); header.append(0)
                var wire = TransferProtocol.hello + TransferFrame(command: .begin, payload: header).encoded()
                for offset in stride(from: 0, to: output.program.count, by: 512) {
                    var chunk = Data(); chunk.appendLE(UInt32(7)); chunk.appendLE(UInt32(offset))
                    chunk.append(output.program[offset..<min(output.program.count, offset + 512)])
                    wire.append(TransferFrame(command: .chunk, payload: chunk).encoded())
                }
                var id = Data(); id.appendLE(UInt32(7))
                wire.append(TransferFrame(command: .commit, payload: id).encoded()); wire.append(TransferFrame(command: .execute, payload: id).encoded())
                try wire.write(to: directory.appendingPathComponent("interop-\(index).wire"))
            }
        }
    }

    func testTimingLimitsCodecAndCapabilities() throws {
        for timing in [TypingTiming.fast, .slow, .variable, .init(pauseMilliseconds: 500, variationMilliseconds: 500), .init(pauseMilliseconds: 1000, variationMilliseconds: 0)] {
            let macro = SavedMacro(name: "Paced", steps: [.init(.text, "x")])
            let output = try MacroCompiler.compile(macro, context: .init(clipboard: "", date: Date()), timing: timing)
            XCTAssertEqual(try MacroProgram.encode(MacroProgram.decode(output.program)), output.program)
            for capabilities: UInt8 in [31, 63, 127, 255] {
                var session = TransferSession(); let helper = TransferProtocolTests()
                var ready = helper.ready(); ready.payload[8] = capabilities
                _ = try session.receive(ready)
                if capabilities & 64 != 0 {
                    _ = try session.receive(.init(command: .keyboardReply, payload: Data([1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
                }
                if timing != .fast && capabilities < 128 { XCTAssertThrowsError(try session.begin(output, jobID: 7)) }
                else { XCTAssertFalse(try session.begin(output, jobID: 7).isEmpty) }
            }
        }
        for (pause, variation) in [(-1, 0), (1001, 0), (20, 21), (900, 101)] {
            XCTAssertFalse(TypingTiming(pauseMilliseconds: pause, variationMilliseconds: variation).isValid)
        }
        XCTAssertThrowsError(try MacroProgram.encode([.text("x"), .typingTiming(.slow)]))
        XCTAssertThrowsError(try MacroProgram.encode([.repeatFor(duration: 1000, intervalMin: 1000, intervalMax: 1000, body: [.typingTiming(.slow), .text("x")])]))
    }
}
