import Foundation

struct ClipboardFrame: Equatable {
    let command: UInt8
    let payload: Data

    func encoded() -> Data {
        precondition(payload.count <= 3072)
        let length = UInt16(payload.count)
        return Data([2, command, UInt8(length & 255), UInt8(length >> 8)]) + payload
    }
}

struct ClipboardFrameDecoder {
    enum DecodeError: Error { case invalidVersion, oversizedResponse }
    private var buffer: [UInt8] = []

    mutating func append(_ bytes: Data) throws -> [ClipboardFrame] {
        buffer.append(contentsOf: bytes)
        var frames: [ClipboardFrame] = []
        while buffer.count >= 4 {
            guard buffer[0] == 2 else {
                buffer.removeAll()
                throw DecodeError.invalidVersion
            }
            let length = Int(buffer[2]) | (Int(buffer[3]) << 8)
            guard length <= 124 else {
                buffer.removeAll()
                throw DecodeError.oversizedResponse
            }
            guard buffer.count >= length + 4 else { break }
            frames.append(ClipboardFrame(command: buffer[1], payload: Data(buffer[4..<(4 + length)])))
            buffer.removeFirst(4 + length)
        }
        return frames
    }
}

enum USBText {
    enum ValidationError: LocalizedError {
        case unsupportedText, invalidSize, invalidLayout
        var errorDescription: String? {
            switch self {
            case .unsupportedText: return "Only ASCII text, tabs and line breaks are supported."
            case .invalidSize: return "Enter between 1 and 3071 ASCII characters."
            case .invalidLayout: return "Choose a supported target keyboard layout."
            }
        }
    }

    static func payload(_ text: String, layout: UInt8) throws -> Data {
        guard layout <= 1 else { throw ValidationError.invalidLayout }
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.count <= 3071 else { throw ValidationError.invalidSize }
        guard bytes.allSatisfy({ (32...126).contains($0) || [9, 10, 13].contains($0) }) else {
            throw ValidationError.unsupportedText
        }
        return Data([layout] + bytes)
    }
}
