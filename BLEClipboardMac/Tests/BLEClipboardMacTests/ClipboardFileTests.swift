import XCTest
@testable import BLEClipboardMac

final class ClipboardFileTests: XCTestCase {
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
        try withFile(Data(repeating: 65, count: 3072)) {
            XCTAssertThrowsError(try ClipboardFile.read($0))
        }
    }

    func testNonASCIIAndBinaryFilesAreRejected() throws {
        try withFile(Data([0xC3, 0xA9])) { XCTAssertThrowsError(try ClipboardFile.read($0)) }
        try withFile(Data([0, 1, 2, 255])) { XCTAssertThrowsError(try ClipboardFile.read($0)) }
    }

    func testMaximumFileAndMissingFile() throws {
        try withFile(Data(repeating: 65, count: 3071)) {
            XCTAssertEqual(try ClipboardFile.read($0).utf8.count, 3071)
        }
        XCTAssertThrowsError(try ClipboardFile.read(URL(fileURLWithPath: "/nonexistent/ble-clipboard-test.txt")))
    }
}
