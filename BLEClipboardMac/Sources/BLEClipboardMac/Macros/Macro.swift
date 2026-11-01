import Foundation

enum TargetSystem: String, Codable, CaseIterable, Identifiable {
    case macOS, windows, linux
    var id: String { rawValue }
}

enum MacroLayout: String, Codable, CaseIterable, Identifiable {
    case us = "QWERTY US"
    case turkishQ = "tr-TR.kl"
    case bosnian = "ba-BA.kl"
    case czech = "cz_CS.kl"
    case danish = "da-DA.kl"
    case germanSwiss = "de-CH.kl"
    case german = "de-DE.kl"
    case dvorak = "dvorak.kl"
    case british = "en-UK.kl"
    case spanish = "es-ES.kl"
    case spanishLatinAmerica = "es-LA.kl"
    case frenchBelgian = "fr-BE.kl"
    case frenchCanadian = "fr-CA.kl"
    case frenchSwiss = "fr-CH.kl"
    case frenchMac = "fr-FR-mac.kl"
    case french = "fr-FR.kl"
    case croatian = "hr-HR.kl"
    case hungarian = "hu-HU.kl"
    case italianMac = "it-IT-mac.kl"
    case italian = "it-IT.kl"
    case japanese = "ja-JP.kl"
    case norwegian = "nb-NO.kl"
    case dutch = "nl-NL.kl"
    case portugueseBrazil = "pt-BR.kl"
    case portuguese = "pt-PT.kl"
    case slovenian = "si-SI.kl"
    case slovak = "sk-SK.kl"
    case swedish = "sv-SE.kl"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .us: return "English (US)"
        case .turkishQ: return "Turkish Q"
        case .bosnian: return "Bosnian"
        case .czech: return "Czech"
        case .danish: return "Danish"
        case .germanSwiss: return "German (Swiss)"
        case .german: return "German"
        case .dvorak: return "Dvorak"
        case .british: return "English (UK)"
        case .spanish: return "Spanish"
        case .spanishLatinAmerica: return "Spanish (Latin America)"
        case .frenchBelgian: return "French (Belgium)"
        case .frenchCanadian: return "French (Canada)"
        case .frenchSwiss: return "French (Swiss)"
        case .frenchMac: return "French (Mac)"
        case .french: return "French"
        case .croatian: return "Croatian"
        case .hungarian: return "Hungarian"
        case .italianMac: return "Italian (Mac)"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .norwegian: return "Norwegian"
        case .dutch: return "Dutch"
        case .portugueseBrazil: return "Portuguese (Brazil)"
        case .portuguese: return "Portuguese"
        case .slovenian: return "Slovenian"
        case .slovak: return "Slovak"
        case .swedish: return "Swedish"
        }
    }
    var responseName: String { self == .us ? rawValue : String(rawValue.dropLast(3)) }
}

struct MacroParameter: Codable, Equatable, Identifiable {
    var id: String
    var label: String
}

struct MacroStep: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case text, template, chord, delay
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return "Literal text"
            case .template: return "Template"
            case .chord: return "Key combination"
            case .delay: return "Delay"
            }
        }
    }
    var id = UUID()
    var kind: Kind
    var value: String
    var milliseconds: Int

    init(_ kind: Kind, _ value: String = "", milliseconds: Int = 250) {
        self.kind = kind
        self.value = value
        self.milliseconds = milliseconds
    }
}

struct SavedMacro: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var target: TargetSystem = .macOS
    var layout: MacroLayout = .us
    var steps: [MacroStep]
    var parameters: [MacroParameter] = []
    var updatedAt = Date()

    static func starters() -> [SavedMacro] {
        [
            SavedMacro(name: "Type Clipboard", steps: [.init(.template, "{{clipboard}}")]),
            SavedMacro(name: "Saved Snippet", steps: [.init(.text, "Hello from BLE Clipboard.")]),
            SavedMacro(name: "Timestamp", steps: [.init(.template, "{{timestamp}}")]),
            SavedMacro(name: "Replace Field", steps: [.init(.chord, "PRIMARY+A"), .init(.template, "{{clipboard}}")]),
            SavedMacro(name: "Fill Two Fields", steps: [
                .init(.template, "{{first}}"), .init(.chord, "TAB"), .init(.template, "{{second}}"),
            ], parameters: [.init(id: "first", label: "First field"), .init(id: "second", label: "Second field")]),
        ]
    }
}

struct MacroDocument: Codable, Equatable {
    var schemaVersion = 1
    var macros: [SavedMacro]
}

enum MacroError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct MacroRunContext {
    var clipboard: String
    var date: Date
    var parameters: [String: String] = [:]
}

struct CompiledMacro {
    let script: String
    let preview: [String]
    let layout: MacroLayout
    var bytes: Int { script.utf8.count }
}

enum MacroCompiler {
    static let maximumBytes = 65_536
    private static let token = try! NSRegularExpression(pattern: #"\{\{([A-Za-z][A-Za-z0-9_]{0,31})\}\}"#)
    private static let parameterName = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9_]{0,31}$"#)
    private static let specialKeys: Set<String> = Set([
        "ENTER", "TAB", "ESC", "BACKSPACE", "DEL", "UP", "DOWN", "LEFT", "RIGHT",
        "HOME", "END", "PGUP", "PGDN", "SPACE",
    ]).union((1...12).map { "F\($0)" })

    static func validate(_ macro: SavedMacro) throws {
        guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              macro.name.count <= 80 else { throw MacroError.invalid("A macro needs a name of 1-80 characters.") }
        guard !macro.steps.isEmpty, macro.steps.count <= 128 else {
            throw MacroError.invalid("A macro needs 1-128 steps.")
        }
        guard Set(macro.steps.map(\.id)).count == macro.steps.count else {
            throw MacroError.invalid("Duplicate step identifiers.")
        }
        guard macro.parameters.count <= 32,
              Set(macro.parameters.map(\.id)).count == macro.parameters.count else {
            throw MacroError.invalid("Parameters must have unique names; maximum 32.")
        }
        for parameter in macro.parameters {
            let range = NSRange(parameter.id.startIndex..., in: parameter.id)
            guard parameterName.firstMatch(in: parameter.id, range: range) != nil,
                  !["clipboard", "timestamp"].contains(parameter.id),
                  !parameter.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  parameter.label.count <= 80 else { throw MacroError.invalid("Invalid parameter name or label.") }
        }
        let known = Set(macro.parameters.map(\.id)).union(["clipboard", "timestamp"])
        var totalDelay = 0
        var hasOutput = false
        for step in macro.steps {
            switch step.kind {
            case .text:
                try validateText(step.value)
                hasOutput = hasOutput || !step.value.isEmpty
            case .template:
                try validateText(step.value)
                for name in try templateTokens(step.value) where !known.contains(name) {
                    throw MacroError.invalid("Unknown parameter: \(name).")
                }
                hasOutput = hasOutput || !step.value.isEmpty
            case .chord:
                _ = try chord(step.value, target: macro.target)
                hasOutput = true
            case .delay:
                guard (1...30_000).contains(step.milliseconds) else {
                    throw MacroError.invalid("Each delay must be 1-30000 ms.")
                }
                totalDelay += step.milliseconds
            }
        }
        guard hasOutput, totalDelay <= 120_000 else {
            throw MacroError.invalid("A macro needs output and at most 120 seconds of explicit delays.")
        }
        guard macro.steps.reduce(0, { $0 + $1.value.utf8.count }) <= maximumBytes else {
            throw MacroError.invalid("Macro definitions exceed the size limit.")
        }
    }

    static func compile(_ macro: SavedMacro, context: MacroRunContext, limit: Int = maximumBytes) throws -> CompiledMacro {
        try validate(macro)
        var script = ""
        var preview: [String] = []
        for step in macro.steps {
            switch step.kind {
            case .text, .template:
                let text = step.kind == .text ? step.value : try expand(step.value, context: context)
                try validateText(text)
                script += escapeLiteral(text)
                preview.append("Text: \(text)")
            case .chord:
                let key = try chord(step.value, target: macro.target)
                script += "[\(key)]"
                preview.append("Key: \(key)")
            case .delay:
                script += "[DELAY:\(step.milliseconds)]"
                preview.append("Delay: \(step.milliseconds) ms")
            }
            guard script.utf8.count <= min(limit, maximumBytes) else {
                throw MacroError.invalid("Expanded macro exceeds the connected device's capacity.")
            }
        }
        guard !script.isEmpty else { throw MacroError.invalid("There is no text or key to send.") }
        return CompiledMacro(script: script, preview: preview, layout: macro.layout)
    }

    static func validateText(_ text: String) throws {
        guard text.utf8.count <= maximumBytes,
              text.utf8.allSatisfy({ (32...126).contains($0) || [9, 10, 13].contains($0) }) else {
            throw MacroError.invalid("USB text supports ASCII, tabs and line breaks only.")
        }
    }

    // Ducker's empty tag emits a literal opening bracket in both typing paths.
    static func escapeLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "[]")
    }

    static func templateTokens(_ text: String) throws -> [String] {
        let matches = token.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var remainder = text
        for match in matches.reversed() {
            if let range = Range(match.range, in: remainder) { remainder.removeSubrange(range) }
        }
        guard !remainder.contains("{{"), !remainder.contains("}}") else {
            throw MacroError.invalid("Malformed template parameter.")
        }
        return matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }

    private static func expand(_ template: String, context: MacroRunContext) throws -> String {
        _ = try templateTokens(template)
        let matches = token.matches(in: template, range: NSRange(template.startIndex..., in: template))
        var result = template
        var byteCount = template.utf8.count
        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: template),
                  let range = Range(match.range, in: result) else { continue }
            let name = String(template[nameRange])
            let value: String
            switch name {
            case "clipboard": value = context.clipboard
            case "timestamp": value = ISO8601DateFormatter().string(from: context.date)
            default:
                guard let supplied = context.parameters[name] else { throw MacroError.invalid("Enter a value for \(name).") }
                value = supplied
            }
            // Replacement values are never recursively interpreted as templates or commands.
            try validateText(value)
            byteCount += value.utf8.count - match.range.length
            guard byteCount <= maximumBytes else { throw MacroError.invalid("Expanded template is too large.") }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    private static func chord(_ value: String, target: TargetSystem) throws -> String {
        let keys = value.uppercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = keys.last, !key.isEmpty, keys.count <= 5 else {
            throw MacroError.invalid("Invalid key combination.")
        }
        let modifiers = keys.dropLast().map { $0 == "PRIMARY" ? (target == .macOS ? "WIN" : "CTRL") : $0 }
        guard Set(modifiers).count == modifiers.count,
              modifiers.allSatisfy({ ["CTRL", "ALT", "SHIFT", "WIN"].contains($0) }),
              specialKeys.contains(key) || (key.utf8.count == 1 && key.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) })) else {
            throw MacroError.invalid("Unsupported key combination: \(value).")
        }
        let outputKey = key.count == 1 ? key.lowercased() : key
        return (Array(modifiers) + [outputKey]).joined(separator: "+")
    }
}
