import Foundation
import Combine

@MainActor
final class MacroLibrary: ObservableObject {
    @Published private(set) var macros: [SavedMacro] = []
    @Published private(set) var error: String?
    private let url: URL
    private let manager: FileManager
    private var writable = false

    init(url: URL? = nil, manager: FileManager = .default) {
        self.manager = manager
        self.url = url ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BLE Clipboard/Macros/library.json")
        do {
            if manager.fileExists(atPath: self.url.path) {
                macros = try Self.decode(Self.read(self.url))
            } else {
                macros = SavedMacro.starters()
            }
            writable = true
        } catch {
            self.error = "Macro library could not be opened. The existing file was left unchanged."
        }
    }

    static func decode(_ data: Data) throws -> [SavedMacro] {
        guard data.count <= 2_000_000 else { throw MacroError.invalid("Library file is too large.") }
        let document = try JSONDecoder().decode(MacroDocument.self, from: data)
        guard document.schemaVersion == 1, document.macros.count <= 1000,
              Set(document.macros.map(\.id)).count == document.macros.count else {
            throw MacroError.invalid("Unsupported library version or duplicate macro identifiers.")
        }
        try document.macros.forEach(MacroCompiler.validate)
        return document.macros
    }

    static func read(_ url: URL) throws -> Data {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw MacroError.invalid("Choose a regular JSON file.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2_000_001) ?? Data()
        guard data.count <= 2_000_000 else { throw MacroError.invalid("Library file is too large.") }
        return data
    }

    func save(_ macro: SavedMacro) throws {
        try MacroCompiler.validate(macro)
        var updated = macro
        updated.updatedAt = Date()
        var next = macros
        if let index = next.firstIndex(where: { $0.id == macro.id }) { next[index] = updated }
        else { next.append(updated) }
        try persist(next)
    }

    func remove(_ id: UUID) throws { try persist(macros.filter { $0.id != id }) }

    func duplicate(_ macro: SavedMacro) throws -> UUID {
        var copy = macro
        copy.id = UUID()
        copy.name = String(macro.name.prefix(70)) + " Copy"
        try save(copy)
        return copy.id
    }

    func importData(_ data: Data) throws -> UUID? {
        let imported = try Self.decode(data)
        let copies = imported.map { macro -> SavedMacro in
            var copy = macro
            copy.id = UUID()
            return copy
        }
        try persist(macros + copies)
        return copies.first?.id
    }

    func exportData(_ ids: Set<UUID>? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(MacroDocument(macros: macros.filter { ids == nil || ids!.contains($0.id) }))
    }

    func recoverBackup() throws {
        let backup = url.appendingPathExtension("backup")
        let data = try Self.read(backup)
        let restored = try Self.decode(data)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        macros = restored
        writable = true
        error = nil
    }

    private func persist(_ next: [SavedMacro]) throws {
        guard writable else { throw MacroError.invalid("Recover the existing library before saving changes.") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(MacroDocument(macros: next))
        _ = try Self.decode(data)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path) {
            let previous = try Self.read(url)
            _ = try Self.decode(previous)
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        macros = next
        error = nil
    }
}
