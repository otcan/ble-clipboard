import Foundation

enum ClipboardFile {
    static func read(_ url: URL, layout: UInt8 = 0) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= MacroProgram.maximumBytes else {
            throw MacroError.invalid("Choose a nonempty UTF-8 text file up to 65536 bytes.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: MacroProgram.maximumBytes + 1) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else {
            throw MacroError.invalid("The file is not valid UTF-8 text.")
        }
        guard let keyboard = KeyboardLayout(wireID: layout) else { throw MacroError.invalid("Unsupported keyboard layout.") }
        _ = try MacroCompiler.compile(SavedMacro(name: "Text File", layout: keyboard, steps: [.init(.text, text)]),
                                      context: .init(clipboard: "", date: Date()))
        return text
    }
}
