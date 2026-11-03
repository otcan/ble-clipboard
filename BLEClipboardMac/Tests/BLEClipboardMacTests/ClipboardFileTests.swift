import XCTest
@testable import BLEClipboardMac

final class ClipboardFileTests: XCTestCase {
    func testTurkishUTF8ImportUsesTheSelectedLayout() throws {
        try withFile(Data("\u{011F}\u{015F}\u{0131}".utf8)) { url in
            XCTAssertEqual(try ClipboardFile.read(url, layout: 1), "\u{011F}\u{015F}\u{0131}")
            XCTAssertThrowsError(try ClipboardFile.read(url, layout: 0))
        }
    }
    private func withFile(_ data: Data, check: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try check(url)
    }

    func testPlainTextPreservesLineBreaks() throws {
        try withFile(Data("Test\r\nline\tend".utf8)) {
            XCTAssertEqual(try ClipboardFile.read($0), "Test\r\nline\tend")
        }
    }

    func testEmptyAndOversizedFilesAreRejected() throws {
        try withFile(Data()) { XCTAssertThrowsError(try ClipboardFile.read($0)) }
        try withFile(Data(repeating: 65, count: 65526)) {
            XCTAssertThrowsError(try ClipboardFile.read($0))
        }
    }

    func testNonASCIIAndBinaryFilesAreRejected() throws {
        try withFile(Data([0xC3, 0xA9])) { XCTAssertThrowsError(try ClipboardFile.read($0)) }
        try withFile(Data([0, 1, 2, 255])) { XCTAssertThrowsError(try ClipboardFile.read($0)) }
    }

    func testMaximumFileAndMissingFile() throws {
        try withFile(Data(repeating: 65, count: 65525)) {
            XCTAssertEqual(try ClipboardFile.read($0).utf8.count, 65525)
        }
        XCTAssertThrowsError(try ClipboardFile.read(URL(fileURLWithPath: "/nonexistent/ble-clipboard-test.txt")))
    }
}
