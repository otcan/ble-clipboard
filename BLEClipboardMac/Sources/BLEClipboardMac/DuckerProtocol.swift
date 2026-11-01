import Foundation

enum DuckerProtocol {
    static let maximumBytes = 65_536
    static let hello = Data("TTF?\n".utf8)
    static let execute = Data("TTFEXEC\n".utf8)
    static let cancel = Data("TTFCANCEL\n".utf8)

    static func frame(_ script: String, capacity: Int) throws -> Data {
        try MacroCompiler.validateText(script)
        let normalized = script.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let payload = Data(normalized.utf8)
        guard !payload.isEmpty, payload.count <= min(capacity, maximumBytes) else {
            throw MacroError.invalid("Text exceeds the connected Flipper's capacity.")
        }
        let header = String(format: "TTF1 %d %08x\n", payload.count, crc32(payload))
        return Data(header.utf8) + payload
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

struct DuckerLineDecoder {
    private var buffer: [UInt8] = []
    mutating func append(_ data: Data) throws -> [String] {
        var lines: [String] = []
        for byte in data {
            guard byte == 10 || byte == 13 || (32...126).contains(byte) else {
                buffer.removeAll()
                throw MacroError.invalid("Invalid response from Flipper.")
            }
            if byte == 10 {
                let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeAll(keepingCapacity: true)
                if !line.isEmpty { lines.append(line) }
            } else {
                guard buffer.count < 1024 else {
                    buffer.removeAll()
                    throw MacroError.invalid("Flipper response is too large.")
                }
                buffer.append(byte)
            }
        }
        return lines
    }
}

struct DuckerSession {
    enum Stage: Equatable { case idle, layout, receiving, verified, executing, cancelling }
    enum Event: Equatable {
        case write(Data), ready(Int), cancelCapability, accepted, progress(Double), waitingUSB
        case done(cancelled: Bool), failed(String), disconnectToCancel
    }
    private(set) var capacity = 0
    private(set) var supportsCancel = false
    private(set) var stage = Stage.idle
    private var script = ""
    private var desiredLayout = ""
    private var layoutResponse = ""
    private var cancelRequested = false

    mutating func begin(_ macro: CompiledMacro) throws -> [Event] {
        guard capacity > 0, stage == .idle else { throw MacroError.invalid("Flipper is not ready for a new macro.") }
        _ = try DuckerProtocol.frame(macro.script, capacity: capacity)
        script = macro.script
        desiredLayout = macro.layout.rawValue
        layoutResponse = macro.layout.responseName
        cancelRequested = false
        stage = .layout
        return [.write(Data("TTFLAYOUT \(desiredLayout)\n".utf8))]
    }

    mutating func cancel() -> [Event] {
        guard stage != .idle else { return [] }
        cancelRequested = true
        if !supportsCancel { return cancelNow() }
        if stage == .layout || stage == .receiving { return [] }
        return cancelNow()
    }

    private mutating func cancelNow() -> [Event] {
        stage = .cancelling
        return supportsCancel ? [.write(DuckerProtocol.cancel)] : [.disconnectToCancel]
    }

    mutating func receive(_ line: String) throws -> [Event] {
        if line.hasPrefix("READY:") {
            let parts = line.split(separator: ":", omittingEmptySubsequences: false)
            guard stage == .idle, parts.count == 3, parts[1] == "1",
                  let limit = Int(parts[2]), (1...DuckerProtocol.maximumBytes).contains(limit) else {
                throw MacroError.invalid("Unsupported Ducker protocol or capacity.")
            }
            capacity = limit
            return [.ready(limit)]
        }
        if line == "CAPS:CANCEL" { supportsCancel = true; return [.cancelCapability] }
        if line.hasPrefix("ERR:") {
            resetJob()
            return [.failed(line)]
        }
        if stage == .layout, line == "LAYOUT:\(layoutResponse)" {
            if cancelRequested { resetJob(); return [.done(cancelled: true)] }
            stage = .receiving
            return [.write(try DuckerProtocol.frame(script, capacity: capacity))]
        }
        if stage == .receiving, line == "RECV" {
            script = ""
            stage = .verified
            if cancelRequested { return cancelNow() }
            return [.write(DuckerProtocol.execute)]
        }
        if stage == .verified, line == "WAIT_USB" { return [.waitingUSB] }
        if stage == .verified, line == "SENDING" {
            stage = .executing
            if cancelRequested { return cancelNow() }
            return [.accepted]
        }
        if stage == .executing, line.hasPrefix("PROGRESS:") {
            guard let percent = Int(line.dropFirst(9)), (0...100).contains(percent) else {
                throw MacroError.invalid("Invalid progress response.")
            }
            return [.progress(Double(percent) / 100)]
        }
        if [.executing, .verified, .cancelling].contains(stage), line == "CANCEL" {
            resetJob()
            return [.done(cancelled: true)]
        }
        if [.executing, .cancelling].contains(stage), line == "OK" {
            resetJob()
            return [.done(cancelled: false)]
        }
        return []
    }

    private mutating func resetJob() {
        stage = .idle
        script = ""
        desiredLayout = ""
        layoutResponse = ""
        cancelRequested = false
    }
}
