import XCTest
@testable import BLEClipboardMac

final class DuckerProtocolTests: XCTestCase {
    func testCRCAndFraming() throws {
        XCTAssertEqual(DuckerProtocol.crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(try DuckerProtocol.frame("abc", capacity: 3), Data("TTF1 3 352441c2\nabc".utf8))
        XCTAssertEqual(try DuckerProtocol.frame("a\r\nb\rc", capacity: 5), try DuckerProtocol.frame("a\nb\nc", capacity: 5))
        XCTAssertThrowsError(try DuckerProtocol.frame("abc", capacity: 2))
    }

    func testFragmentedAndRepeatedStatusLines() throws {
        var decoder = DuckerLineDecoder()
        XCTAssertEqual(try decoder.append(Data("REA".utf8)), [])
        XCTAssertEqual(try decoder.append(Data("DY:1:65536\r\nLAYOUT:QWERTY US\n".utf8)), ["READY:1:65536", "LAYOUT:QWERTY US"])
        XCTAssertEqual(try decoder.append(Data("OK\nCANCEL\n".utf8)), ["OK", "CANCEL"])
        XCTAssertThrowsError(try decoder.append(Data(repeating: 65, count: 1025)))
        XCTAssertThrowsError(try decoder.append(Data([255])))
    }

    func testExecutionWaitsForLayoutAndVerifiedFrame() throws {
        var session = DuckerSession()
        XCTAssertEqual(try session.receive("READY:1:65536"), [.ready(65536)])
        let plan = CompiledMacro(script: "abc", preview: [], layout: .us)
        XCTAssertEqual(try session.begin(plan), [.write(Data("TTFLAYOUT QWERTY US\n".utf8))])
        XCTAssertEqual(try session.receive("RECV"), [])
        XCTAssertEqual(try session.receive("LAYOUT:QWERTY US"), [.write(try DuckerProtocol.frame("abc", capacity: 65536))])
        XCTAssertEqual(try session.receive("RECV"), [.write(DuckerProtocol.execute)])
        XCTAssertEqual(try session.receive("WAIT_USB"), [.waitingUSB])
        XCTAssertEqual(try session.receive("SENDING"), [.accepted])
        XCTAssertEqual(try session.receive("PROGRESS:50"), [.progress(0.5)])
        XCTAssertEqual(try session.receive("OK"), [.done(cancelled: false)])
        XCTAssertEqual(session.stage, .idle)
    }

    func testCancellationDuringReceiveNeverExecutes() throws {
        var session = DuckerSession()
        _ = try session.receive("READY:1:65536")
        _ = try session.receive("CAPS:CANCEL")
        _ = try session.begin(.init(script: "abc", preview: [], layout: .us))
        _ = try session.receive("LAYOUT:QWERTY US")
        XCTAssertEqual(session.cancel(), [])
        XCTAssertEqual(try session.receive("RECV"), [.write(DuckerProtocol.cancel)])
        XCTAssertEqual(try session.receive("CANCEL"), [.done(cancelled: true)])
    }

    func testTurkishLayoutAcknowledgementDropsFileExtension() throws {
        var session = DuckerSession()
        _ = try session.receive("READY:1:65536")
        XCTAssertEqual(try session.begin(.init(script: "abc", preview: [], layout: .turkishQ)),
                       [.write(Data("TTFLAYOUT tr-TR.kl\n".utf8))])
        XCTAssertEqual(try session.receive("LAYOUT:QWERTY US"), [])
        XCTAssertEqual(try session.receive("LAYOUT:tr-TR"), [.write(try DuckerProtocol.frame("abc", capacity: 65536))])
    }

    func testOnlyOneJobAndCancellationBeforeLayoutNeverTransfers() throws {
        var session = DuckerSession()
        _ = try session.receive("READY:1:65536")
        _ = try session.receive("CAPS:CANCEL")
        let macro = CompiledMacro(script: "abc", preview: [], layout: .us)
        _ = try session.begin(macro)
        XCTAssertThrowsError(try session.begin(macro))
        XCTAssertEqual(session.cancel(), [])
        XCTAssertEqual(try session.receive("LAYOUT:QWERTY US"), [.done(cancelled: true)])
        XCTAssertEqual(try session.receive("RECV"), [])
        XCTAssertEqual(try session.receive("SENDING"), [])
    }

    func testUnpatchedDuckerStopsImmediatelyWhileReceiving() throws {
        var session = DuckerSession()
        _ = try session.receive("READY:1:65536")
        _ = try session.begin(.init(script: "abc", preview: [], layout: .us))
        _ = try session.receive("LAYOUT:QWERTY US")
        XCTAssertEqual(session.cancel(), [.disconnectToCancel])
        XCTAssertEqual(try session.receive("RECV"), [])
    }

    func testErrorsDoNotScheduleExecutionAndOldPeersCancelByDisconnect() throws {
        var session = DuckerSession()
        XCTAssertThrowsError(try session.receive("READY:2:65536"))
        _ = try session.receive("READY:1:255")
        _ = try session.begin(.init(script: "abc", preview: [], layout: .us))
        _ = try session.receive("LAYOUT:QWERTY US")
        XCTAssertEqual(try session.receive("ERR:CHECKSUM"), [.failed("ERR:CHECKSUM")])
        XCTAssertEqual(try session.receive("RECV"), [])
        _ = try session.begin(.init(script: "abc", preview: [], layout: .us))
        _ = try session.receive("LAYOUT:QWERTY US")
        _ = try session.receive("RECV")
        _ = try session.receive("SENDING")
        XCTAssertEqual(session.cancel(), [.disconnectToCancel])
    }
}
