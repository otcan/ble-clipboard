import Foundation

struct KeyboardSettings: Codable, Equatable {
    var layout: KeyboardLayout = .us
    var target: TargetSystem = .macOS
    var useForSavedRuns = false
    var revision: UInt32 = 0

    private static let key = "keyboard-settings-v1"

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }

    func store(in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    func requestPayload(id: UInt16) -> Data {
        var data = Data(); data.appendLE(id)
        data.append(contentsOf: [1, layout.wireID, target.wireID, useForSavedRuns ? 1 : 0])
        data.appendLE(revision)
        return data
    }
}

struct KeyboardSettingsReply {
    let requestID: UInt16
    let result: UInt8
    let settings: KeyboardSettings

    init?(payload: Data) {
        guard payload.count == 11 else { return nil }
        var reader = BinaryReader(payload)
        guard (try? reader.byte()) == 1, let request = try? reader.u16(), let code = try? reader.byte(), code <= 5,
              let layoutID = try? reader.byte(), let layout = KeyboardLayout(wireID: layoutID),
              let targetID = try? reader.byte(), Int(targetID) < TargetSystem.allCases.count,
              let saved = try? reader.byte(), saved <= 1, let revision = try? reader.u32() else { return nil }
        guard revision != 0 || (layout == .us && targetID == 0 && saved == 0) else { return nil }
        requestID = request; result = code
        settings = .init(layout: layout, target: TargetSystem.allCases[Int(targetID)], useForSavedRuns: saved == 1, revision: revision)
    }

    var error: String? {
        switch result {
        case 0: return nil
        case 1: return "Keyboard changed on Flipper. Review the current setting before changing it again."
        case 2: return "Flipper is busy. Stop the job before changing its keyboard."
        case 3: return "Flipper rejected the keyboard setting."
        case 4: return "Keyboard layout unavailable on Flipper. Check its SD layout assets."
        default: return "Keyboard was not saved on Flipper. Check its SD card; the previous setting is unchanged."
        }
    }
}
