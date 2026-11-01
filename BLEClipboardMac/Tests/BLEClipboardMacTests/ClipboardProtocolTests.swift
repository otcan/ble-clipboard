import XCTest
@testable import BLEClipboardMac

final class ClipboardProtocolTests: XCTestCase {
    func testFragmentedAndRepeatedResponses() throws {
        var decoder = ClipboardFrameDecoder()
        let first = ClipboardFrame(command: 0x81, payload: Data("Rapigak".utf8))
        let second = ClipboardFrame(command: 0x83, payload: Data("typed".utf8))
        let bytes = first.encoded()
        XCTAssertEqual(try decoder.append(bytes.prefix(3)), [])
        XCTAssertEqual(try decoder.append(bytes.dropFirst(3)), [first])
        XCTAssertEqual(try decoder.append(second.encoded()), [second])
        XCTAssertEqual(try decoder.append(first.encoded() + second.encoded()), [first, second])
    }

    func testInvalidHeadersResetDecoder() throws {
        var decoder = ClipboardFrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([1, 0x81, 0, 0])))
        XCTAssertThrowsError(try decoder.append(Data([2, 0x81, 255, 255])))
        let valid = ClipboardFrame(command: 0x83, payload: Data())
        XCTAssertEqual(try decoder.append(valid.encoded()), [valid])
    }

    func testMaximumTextFrame() {
        let text = Data(repeating: 65, count: 3072)
        let bytes = ClipboardFrame(command: 2, payload: text).encoded()
        XCTAssertEqual(Array(bytes.prefix(4)), [2, 2, 0, 12])
        XCTAssertEqual(bytes.count, 3076)
    }

    func testUSBTextValidation() throws {
        XCTAssertEqual(try USBText.payload("Hello\n\t", layout: 1), Data([1] + Array("Hello\n\t".utf8)))
        XCTAssertThrowsError(try USBText.payload("", layout: 0))
        XCTAssertThrowsError(try USBText.payload("\u{00E9}", layout: 0))
        XCTAssertThrowsError(try USBText.payload("\u{1B}", layout: 0))
        XCTAssertThrowsError(try USBText.payload("text", layout: 2))
        XCTAssertEqual(try USBText.payload(String(repeating: "a", count: 3071), layout: 0).count, 3072)
        XCTAssertThrowsError(try USBText.payload(String(repeating: "a", count: 3072), layout: 0))
    }
}
