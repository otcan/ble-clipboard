import Foundation

enum TransferCommand: UInt8 {
    case hello = 1, begin = 2, chunk = 3, commit = 4, execute = 5, cancel = 6, save = 7, info = 8
    case getKeyboard = 9, setKeyboard = 10
    case ready = 0x81, begun = 0x82, chunked = 0x83, verified = 0x84
    case started = 0x85, waitingUSB = 0x86, progress = 0x87, done = 0x88, error = 0xFF
    case saved = 0x89, active = 0x8A, infoReply = 0x8B
    case keyboardReply = 0x8C
}

enum TransferDestination: String, CaseIterable, Identifiable {
    case run = "Run on USB", save = "Save to Flipper"
    var id: String { rawValue }
}

struct SavedProgramRequest {
    let id: UUID
    let name: String
    func payload(jobID: UInt32) throws -> Data {
        let bytes = Data(name.utf8)
        guard (1...79).contains(bytes.count), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw MacroError.invalid("The Flipper name must be 1-79 UTF-8 bytes, with no control characters.")
        }
        var result = Data(); result.appendLE(jobID)
        var uuid = id.uuid
        result.append(withUnsafeBytes(of: &uuid) { Data($0) })
        guard result.dropFirst(4).contains(where: { $0 != 0 }) else { throw MacroError.invalid("Invalid saved macro identifier.") }
        result.append(UInt8(bytes.count)); result.append(bytes)
        return result
    }
}

struct TransferFrame: Equatable {
    let command: TransferCommand
    var payload = Data()
    func encoded() -> Data {
        precondition(payload.count <= 520)
        var result = Data([4, command.rawValue])
        result.appendLE(UInt16(payload.count)); result.append(payload)
        return result
    }
}

struct TransferFrameDecoder {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [TransferFrame] {
        var frames: [TransferFrame] = []
        for byte in data {
            buffer.append(byte)
            guard buffer.first == 4 else { buffer.removeAll(); throw MacroError.invalid("Incompatible Flipper app. Install BLE Clipboard \(BuildRelease.version).") }
            if buffer.count >= 4 {
                let bytes = Array(buffer.prefix(4))
                let size = Int(bytes[2]) | (Int(bytes[3]) << 8)
                guard size <= 124, let command = TransferCommand(rawValue: bytes[1]), command.rawValue >= 0x81 else {
                    buffer.removeAll(); throw MacroError.invalid("Invalid Flipper response header.")
                }
                if buffer.count == size + 4 {
                    frames.append(.init(command: command, payload: Data(buffer.dropFirst(4))))
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        }
        return frames
    }
}

enum TransferProtocol {
    static let maximumBytes = MacroProgram.maximumBytes
    static let hello = TransferFrame(command: .hello, payload: Data("BLECLIP/4".utf8)).encoded()
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

struct TransferSession {
    enum Stage: Equatable { case idle, beginning, receiving, committing, saving, waitingUSB, executing, cancelling }
    enum Event: Equatable {
        case write(Data), ready(Int, String), accepted, progress(Double), waitingUSB
        case done(cancelled: Bool), failed(String, saving: Bool)
        case saved, resumed, timer(elapsed: UInt32, remaining: UInt32), companionInfo(CompanionInfo)
        case keyboardSettings(KeyboardSettings), keyboardSyncFailed(String)
    }
    private(set) var capacity = 0
    private(set) var stage = Stage.idle
    private(set) var jobID: UInt32 = 0
    private(set) var autonomous = false
    private var savedRequest: SavedProgramRequest?
    var isSaving: Bool { savedRequest != nil }
    private var executionTotal: UInt32 = 0
    private var chunkSize = 0
    private var layoutCount: UInt8 = 0
    private var targetMask: UInt8 = 0
    private var program = Data()
    private var sentOffset = 0
    private var acknowledgedOffset = 0
    private var executionOffset: UInt32 = 0
    private var cancelRequested = false
    private var awaitingInfo = false
    private(set) var supportsKeyboardSync = false
    private(set) var supportsTypingTiming = false
    private(set) var keyboardSettings: KeyboardSettings?
    private var keyboardRequestID: UInt16 = 0
    private var pendingKeyboardID: UInt16?
    var keyboardSyncPending: Bool { pendingKeyboardID != nil }

    mutating func requestKeyboardSettings() throws -> [Event] {
        guard supportsKeyboardSync, !keyboardSyncPending else { throw MacroError.invalid("Keyboard sync is unavailable or already pending.") }
        keyboardRequestID = keyboardRequestID == .max ? 1 : keyboardRequestID + 1
        pendingKeyboardID = keyboardRequestID
        var payload = Data(); payload.appendLE(keyboardRequestID)
        return [write(.getKeyboard, payload)]
    }

    mutating func setKeyboardSettings(_ settings: KeyboardSettings) throws -> [Event] {
        guard supportsKeyboardSync, !keyboardSyncPending, stage == .idle, let current = keyboardSettings,
              current.revision == settings.revision else { throw MacroError.invalid("Keyboard is not ready to change. Refresh it while Flipper is idle.") }
        keyboardRequestID = keyboardRequestID == .max ? 1 : keyboardRequestID + 1
        pendingKeyboardID = keyboardRequestID
        return [write(.setKeyboard, settings.requestPayload(id: keyboardRequestID))]
    }

    mutating func keyboardSyncTimedOut() -> [Event] {
        guard keyboardSyncPending else { return [] }
        pendingKeyboardID = nil
        return [.keyboardSyncFailed("Keyboard sync timed out. Refresh to check Flipper before changing it again.")]
    }

    mutating func begin(_ macro: CompiledMacro, jobID: UInt32 = UInt32.random(in: 1...UInt32.max),
                        saved: SavedProgramRequest? = nil, standalone: Bool = false) throws -> [Event] {
        guard capacity > 0, stage == .idle, jobID != 0, !keyboardSyncPending else { throw MacroError.invalid("Flipper is not ready for a new macro.") }
        guard !macro.usesTypingTiming || supportsTypingTiming else {
            throw MacroError.invalid("Update the Flipper companion to use slower or variable typing, or choose Fast.")
        }
        guard macro.bytes <= capacity, macro.layout.wireID < layoutCount,
              targetMask & (1 << macro.target.wireID) != 0 else { throw MacroError.invalid("The Flipper cannot run this macro or layout.") }
        if let saved { _ = try saved.payload(jobID: jobID) }
        self.jobID = jobID
        savedRequest = saved
        autonomous = standalone && saved == nil
        executionTotal = UInt32(macro.bytes)
        program = macro.program
        sentOffset = 0; acknowledgedOffset = 0; executionOffset = 0; cancelRequested = false
        var payload = idPayload()
        payload.append(macro.layout.wireID); payload.append(macro.target.wireID)
        payload.appendLE(UInt32(program.count)); payload.appendLE(TransferProtocol.crc32(program))
        payload.append(saved != nil ? 2 : autonomous ? 1 : 0)
        stage = .beginning
        return [write(.begin, payload)]
    }

    mutating func cancel() -> [Event] {
        guard stage != .idle, stage != .cancelling else { return [] }
        cancelRequested = true
        if [.beginning, .receiving, .committing, .saving].contains(stage) { return [] }
        return cancelNow()
    }

    private func idPayload() -> Data { var result = Data(); result.appendLE(jobID); return result }
    private func write(_ command: TransferCommand, _ payload: Data) -> Event {
        .write(TransferFrame(command: command, payload: payload).encoded())
    }
    private mutating func cancelNow() -> [Event] { stage = .cancelling; return [write(.cancel, idPayload())] }
    private mutating func nextChunk() -> [Event] {
        if cancelRequested { return cancelNow() }
        if acknowledgedOffset == program.count { stage = .committing; return [write(.commit, idPayload())] }
        var payload = idPayload()
        payload.appendLE(UInt32(acknowledgedOffset))
        sentOffset = min(acknowledgedOffset + chunkSize, program.count)
        payload.append(program.subdata(in: acknowledgedOffset..<sentOffset))
        stage = .receiving
        return [write(.chunk, payload)]
    }
    private mutating func resetJob() {
        stage = .idle; jobID = 0; program = Data(); cancelRequested = false
        sentOffset = 0; acknowledgedOffset = 0; executionOffset = 0
        executionTotal = 0; savedRequest = nil; autonomous = false
    }

    mutating func receive(_ frame: TransferFrame) throws -> [Event] {
        var reader = BinaryReader(frame.payload)
        if frame.command == .ready {
            guard stage == .idle, capacity == 0, (10...41).contains(frame.payload.count) else {
                throw MacroError.invalid("Unexpected Flipper handshake.")
            }
            let limit = Int(try reader.u32()), chunk = Int(try reader.u16())
            let layouts = try reader.byte(), targets = try reader.byte()
            let capabilities = try reader.byte()
            guard (6...TransferProtocol.maximumBytes).contains(limit), (1...512).contains(chunk),
                  layouts == KeyboardLayout.allCases.count, targets & 7 == 7, capabilities & 31 == 31,
                  let name = String(data: try reader.data(reader.remaining), encoding: .utf8), !name.isEmpty else {
                throw MacroError.invalid("Update the Flipper companion to BLE Clipboard \(BuildRelease.version) for Move Mouse and Repeat.")
            }
            capacity = limit; chunkSize = chunk; layoutCount = layouts; targetMask = targets
            awaitingInfo = capabilities & 32 != 0
            supportsKeyboardSync = capabilities & 64 != 0
            supportsTypingTiming = capabilities & 128 != 0
            return [.ready(limit, name)] + (awaitingInfo ? [.write(TransferFrame(command: .info).encoded())] : []) +
                (supportsKeyboardSync ? try requestKeyboardSettings() : [])
        }
        if frame.command == .infoReply {
            guard awaitingInfo, capacity > 0, let info = CompanionInfo(payload: frame.payload) else { return [] }
            awaitingInfo = false
            return [.companionInfo(info)]
        }
        if frame.command == .keyboardReply {
            guard supportsKeyboardSync, let reply = KeyboardSettingsReply(payload: frame.payload),
                  reply.requestID == pendingKeyboardID || (reply.requestID == 0 && reply.result == 0) else { return [] }
            let acknowledges = reply.requestID == pendingKeyboardID
            if acknowledges { pendingKeyboardID = nil }
            var events: [Event] = []
            if reply.settings.revision >= (keyboardSettings?.revision ?? 0) {
                keyboardSettings = reply.settings
                events.append(.keyboardSettings(reply.settings))
            }
            if acknowledges, let error = reply.error { events.append(.keyboardSyncFailed(error)) }
            return events
        }
        let id = try reader.u32()
        if frame.command == .active {
            let total = try reader.u32(), elapsed = try reader.u32(), remaining = try reader.u32()
            let flags = try reader.byte()
            guard reader.remaining == 0, id != 0, (6...65_536).contains(total), flags == 1,
                  remaining <= 86_400_000 else { throw MacroError.invalid("Invalid standalone job status.") }
            guard stage == .idle, capacity > 0 else { return [] }
            jobID = id; executionTotal = total; autonomous = true; stage = .executing
            return [.resumed, .timer(elapsed: elapsed / 1_000, remaining: (remaining + 999) / 1_000)]
        }
        if frame.command == .error {
            let code = try reader.byte()
            guard id == 0 || id == jobID else { return [] }
            let message = String(data: try reader.data(reader.remaining), encoding: .utf8) ?? "Device error \(code)"
            let saving = isSaving
            resetJob()
            return [.failed(message, saving: saving)]
        }
        guard stage != .idle, id == jobID else { return [] }
        switch frame.command {
        case .begun:
            guard reader.remaining == 0, stage == .beginning else { return [] }
            return nextChunk()
        case .chunked:
            let offset = Int(try reader.u32())
            guard reader.remaining == 0, stage == .receiving else { return [] }
            if offset == acknowledgedOffset { return [] }
            guard offset == sentOffset, offset > acknowledgedOffset else { throw MacroError.invalid("Unexpected transfer offset.") }
            acknowledgedOffset = offset
            return [.progress(Double(offset) / Double(program.count) * 0.25)] + nextChunk()
        case .verified:
            guard reader.remaining == 0, stage == .committing else { return [] }
            if cancelRequested { return cancelNow() }
            if let savedRequest {
                stage = .saving
                return [write(.save, try savedRequest.payload(jobID: jobID))]
            }
            stage = .waitingUSB
            return [write(.execute, idPayload())]
        case .waitingUSB:
            guard reader.remaining == 0, stage == .waitingUSB else { return [] }
            return [.waitingUSB]
        case .started:
            guard reader.remaining == 0, stage == .waitingUSB else { return [] }
            stage = .executing
            return [.accepted]
        case .progress:
            let offset = try reader.u32(), total = try reader.u32()
            let elapsed = try reader.u32(), remaining = try reader.u32()
            guard reader.remaining == 0, [.waitingUSB, .executing].contains(stage) else { return [] }
            guard total == executionTotal, offset <= total, offset >= executionOffset, remaining <= 86_400_000 else { throw MacroError.invalid("Invalid execution progress.") }
            let started = stage == .waitingUSB
            stage = .executing; executionOffset = offset
            return (started ? [.accepted] : []) + [.progress(0.25 + Double(offset) / Double(total) * 0.75),
                .timer(elapsed: elapsed / 1_000, remaining: (remaining + 999) / 1_000)]
        case .saved:
            guard reader.remaining == 0, stage == .saving else { return [] }
            resetJob()
            return [.saved]
        case .done:
            let result = try reader.byte()
            guard reader.remaining == 0, result <= 1 else { throw MacroError.invalid("Invalid completion response.") }
            guard result == 1 || [.waitingUSB, .executing, .cancelling].contains(stage) else { return [] }
            resetJob()
            return [.done(cancelled: result == 1)]
        default: throw MacroError.invalid("Unexpected Flipper response.")
        }
    }
}
