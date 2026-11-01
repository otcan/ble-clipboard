import Foundation

enum ClipboardFile {
    static func read(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= 3071 else {
            throw USBText.ValidationError.invalidSize
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 3072) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else {
            throw USBText.ValidationError.unsupportedText
        }
        _ = try USBText.payload(text, layout: 0)
        return text
    }
}
