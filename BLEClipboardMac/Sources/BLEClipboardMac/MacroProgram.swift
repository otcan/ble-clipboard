import Foundation

indirect enum MacroOperation: Equatable {
    case text(String)
    case key(modifiers: UInt8, code: UInt16)
    case delay(UInt32)
    case typingTiming(TypingTiming)
    case mouseJiggle(duration: UInt32, interval: UInt32)
    case moveMouse(xMin: Int8, xMax: Int8, yMin: Int8, yMax: Int8)
    case repeatFor(duration: UInt32, intervalMin: UInt32, intervalMax: UInt32, body: [MacroOperation])

    var hasMouse: Bool {
        switch self {
        case .mouseJiggle, .moveMouse: return true
        case .repeatFor(_, _, _, let body): return body.contains { $0.hasMouse }
        default: return false
        }
    }
}

enum MacroKey {
    static let special: [String: UInt16] = [
        "ENTER": 0x100, "TAB": 0x101, "ESC": 0x102, "BACKSPACE": 0x103,
        "DEL": 0x104, "UP": 0x105, "DOWN": 0x106, "LEFT": 0x107,
        "RIGHT": 0x108, "HOME": 0x109, "END": 0x10A, "PGUP": 0x10B,
        "PGDN": 0x10C, "SPACE": 0x10D,
    ].merging(Dictionary(uniqueKeysWithValues: (1...12).map { ("F\($0)", UInt16(0x10F + $0)) })) { first, _ in first }

    static func valid(_ code: UInt16) -> Bool {
        (97...122).contains(code) || (48...57).contains(code) || special.values.contains(code)
    }
}

struct BinaryReader {
    private let bytes: [UInt8]
    private(set) var offset = 0
    var remaining: Int { bytes.count - offset }
    init(_ data: Data) { bytes = Array(data) }
    mutating func data(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw MacroError.invalid("Truncated binary data.") }
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }
    mutating func byte() throws -> UInt8 { try data(1).first! }
    mutating func u16() throws -> UInt16 {
        let value = Array(try data(2))
        return UInt16(value[0]) | (UInt16(value[1]) << 8)
    }
    mutating func u32() throws -> UInt32 {
        let value = Array(try data(4))
        return UInt32(value[0]) | (UInt32(value[1]) << 8) | (UInt32(value[2]) << 16) | (UInt32(value[3]) << 24)
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, through: 24, by: 8) { append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
}

enum MacroProgram {
    static let maximumBytes = 65_536
    static let magic = Data("BCM4".utf8)
    private struct Budget {
        var delay: UInt32 = 0
        var timed: UInt32 = 0
        var nodes = 0
    }

    static func encode(_ operations: [MacroOperation]) throws -> Data {
        var budget = Budget()
        let records = try encodeRecords(operations, inRepeat: false, budget: &budget)
        var result = magic
        result.appendLE(UInt16(operations.count)); result.append(records)
        guard result.count <= maximumBytes else { throw MacroError.invalid("Encoded macro exceeds 65536 bytes.") }
        return result
    }

    private static func encodeRecords(_ operations: [MacroOperation], inRepeat: Bool, budget: inout Budget) throws -> Data {
        guard !operations.isEmpty, operations.count <= 128 else { throw MacroError.invalid("A program needs 1-128 operations.") }
        var result = Data()
        var hasOutput = false
        for (index, operation) in operations.enumerated() {
            budget.nodes += 1
            guard budget.nodes <= 512 else { throw MacroError.invalid("A program permits at most 512 total operations.") }
            switch operation {
            case .typingTiming(let timing):
                guard !inRepeat, index == 0, timing.isValid else {
                    throw MacroError.invalid("Typing pause must be 0–1000 ms; variation must keep it within that range. Timing belongs at the start of a program.")
                }
                result.append(7)
                result.appendLE(UInt16(timing.pauseMilliseconds))
                result.appendLE(UInt16(timing.variationMilliseconds))
            case .text(let text):
                let bytes = Data(text.utf8)
                guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw MacroError.invalid("Invalid text operation size.") }
                result.append(1); result.appendLE(UInt32(bytes.count)); result.append(bytes)
                hasOutput = true
            case .key(let modifiers, let code):
                guard modifiers & 0xF0 == 0, MacroKey.valid(code) else { throw MacroError.invalid("Invalid key operation.") }
                result.append(2); result.append(modifiers); result.appendLE(code)
                hasOutput = true
            case .delay(let milliseconds):
                guard (1...30_000).contains(milliseconds) else { throw MacroError.invalid("Invalid delay operation.") }
                guard budget.delay <= 120_000 - milliseconds else { throw MacroError.invalid("Explicit delays exceed 120 seconds.") }
                budget.delay += milliseconds
                result.append(3); result.appendLE(milliseconds)
            case .mouseJiggle(let duration, let interval):
                guard !inRepeat, (1...86_400_000).contains(duration), (1_000...3_600_000).contains(interval),
                      budget.timed <= 86_400_000 - duration else {
                    throw MacroError.invalid("Mouse Jiggle allows at most 24 hours total and intervals of 1-3600 seconds.")
                }
                budget.timed += duration
                result.append(4); result.appendLE(duration); result.appendLE(interval)
                hasOutput = true
            case .moveMouse(let xMin, let xMax, let yMin, let yMax):
                guard xMin >= -127, yMin >= -127, xMin <= xMax, yMin <= yMax,
                      xMin != 0 || xMax != 0 || yMin != 0 || yMax != 0 else {
                    throw MacroError.invalid("Move Mouse needs ordered X/Y ranges within -127...127 and a nonzero movement.")
                }
                result.append(contentsOf: [5, UInt8(bitPattern: xMin), UInt8(bitPattern: xMax),
                                           UInt8(bitPattern: yMin), UInt8(bitPattern: yMax)])
                hasOutput = true
            case .repeatFor(let duration, let intervalMin, let intervalMax, let body):
                guard !inRepeat, (1...86_400_000).contains(duration), intervalMin >= 1_000,
                      intervalMin <= intervalMax, intervalMax <= 3_600_000,
                      budget.timed <= 86_400_000 - duration else {
                    throw MacroError.invalid("Repeat allows at most 24 hours total, a 1-3600 second pause range, and no nested repeats.")
                }
                budget.timed += duration
                let records = try encodeRecords(body, inRepeat: true, budget: &budget)
                result.append(6); result.appendLE(duration); result.appendLE(intervalMin); result.appendLE(intervalMax)
                result.appendLE(UInt16(body.count)); result.appendLE(UInt32(records.count)); result.append(records)
                hasOutput = true
            }
            guard result.count <= maximumBytes else { throw MacroError.invalid("Encoded macro exceeds 65536 bytes.") }
        }
        guard hasOutput else { throw MacroError.invalid("A program needs text, a key or mouse movement.") }
        return result
    }

    static func decode(_ data: Data) throws -> [MacroOperation] {
        guard data.count <= maximumBytes else { throw MacroError.invalid("Oversized program.") }
        var reader = BinaryReader(data)
        guard try reader.data(4) == magic else { throw MacroError.invalid("Unsupported program version.") }
        let count = try reader.u16()
        var nodes = 0
        let operations = try decodeRecords(&reader, count: Int(count), inRepeat: false, nodes: &nodes)
        guard reader.remaining == 0, try encode(operations) == data else { throw MacroError.invalid("Invalid program encoding.") }
        return operations
    }

    private static func decodeRecords(_ reader: inout BinaryReader, count: Int, inRepeat: Bool, nodes: inout Int) throws -> [MacroOperation] {
        guard (1...128).contains(count) else { throw MacroError.invalid("Invalid operation count.") }
        var operations: [MacroOperation] = []
        for _ in 0..<count {
            nodes += 1
            guard nodes <= 512 else { throw MacroError.invalid("Too many operations.") }
            switch try reader.byte() {
            case 1:
                let size = try reader.u32()
                guard let text = String(data: try reader.data(Int(size)), encoding: .utf8) else {
                    throw MacroError.invalid("Invalid UTF-8 text operation.")
                }
                operations.append(.text(text))
            case 2: operations.append(.key(modifiers: try reader.byte(), code: try reader.u16()))
            case 3: operations.append(.delay(try reader.u32()))
            case 4:
                guard !inRepeat else { throw MacroError.invalid("Legacy timed mouse operation cannot be repeated.") }
                operations.append(.mouseJiggle(duration: try reader.u32(), interval: try reader.u32()))
            case 5:
                operations.append(.moveMouse(xMin: Int8(bitPattern: try reader.byte()), xMax: Int8(bitPattern: try reader.byte()),
                                             yMin: Int8(bitPattern: try reader.byte()), yMax: Int8(bitPattern: try reader.byte())))
            case 6:
                guard !inRepeat else { throw MacroError.invalid("Nested repeats are not supported.") }
                let duration = try reader.u32(), low = try reader.u32(), high = try reader.u32()
                let count = Int(try reader.u16()), size = Int(try reader.u32())
                var bodyReader = BinaryReader(try reader.data(size))
                let body = try decodeRecords(&bodyReader, count: count, inRepeat: true, nodes: &nodes)
                guard bodyReader.remaining == 0 else { throw MacroError.invalid("Invalid repeat body length.") }
                operations.append(.repeatFor(duration: duration, intervalMin: low, intervalMax: high, body: body))
            case 7:
                guard !inRepeat, operations.isEmpty else { throw MacroError.invalid("Typing timing must be the first program operation.") }
                operations.append(.typingTiming(.init(pauseMilliseconds: Int(try reader.u16()),
                                                     variationMilliseconds: Int(try reader.u16()))))
            default: throw MacroError.invalid("Unknown macro operation.")
            }
        }
        return operations
    }
}
