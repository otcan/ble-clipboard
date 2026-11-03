import Foundation

enum TargetSystem: String, Codable, CaseIterable, Identifiable {
    case macOS, windows, linux
    var id: String { rawValue }
    var wireID: UInt8 { UInt8(Self.allCases.firstIndex(of: self)!) }
}

typealias MacroLayout = KeyboardLayout

struct MacroParameter: Codable, Equatable, Identifiable {
    var id: String
    var label: String
}

struct MacroStep: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case text, template, chord, delay, moveMouse, repeatFor, mouseJiggle
        static let allCases: [Kind] = [.text, .template, .chord, .delay, .moveMouse, .repeatFor]
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return "Literal text"
            case .template: return "Template"
            case .chord: return "Key combination"
            case .delay: return "Delay"
            case .mouseJiggle: return "Mouse Jiggle"
            case .moveMouse: return "Move Mouse"
            case .repeatFor: return "Repeat"
            }
        }
    }
    var id = UUID()
    var kind: Kind
    var value: String
    var milliseconds: Int
    var mouseDurationSeconds: Int?
    var mouseIntervalSeconds: Int?
    var mouseIntervalMaximumSeconds: Int?
    var varyingInterval: Bool?
    var mouseXMinimum: Int?
    var mouseXMaximum: Int?
    var mouseYMinimum: Int?
    var mouseYMaximum: Int?
    var varyingMouse: Bool?
    var children: [MacroStep]?

    var jiggleDuration: Int { mouseDurationSeconds ?? 28_800 }
    var jiggleInterval: Int { mouseIntervalSeconds ?? 60 }
    var intervalMaximum: Int { varyingInterval == true ? (mouseIntervalMaximumSeconds ?? jiggleInterval) : jiggleInterval }
    var xMinimum: Int { mouseXMinimum ?? 1 }
    var xMaximum: Int { varyingMouse == true ? (mouseXMaximum ?? xMinimum) : xMinimum }
    var yMinimum: Int { mouseYMinimum ?? 0 }
    var yMaximum: Int { varyingMouse == true ? (mouseYMaximum ?? yMinimum) : yMinimum }
    var summary: String {
        switch kind {
        case .delay: return "\(milliseconds) ms"
        case .mouseJiggle: return "\(jiggleDuration / 60) min; every \(jiggleInterval) s"
        case .moveMouse: return "X \(xMinimum)...\(xMaximum), Y \(yMinimum)...\(yMaximum) HID units"
        case .repeatFor: return "\(jiggleDuration / 60) min; interval \(jiggleInterval)...\(intervalMaximum) s"
        default: return value
        }
    }

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

    static func mouseJiggler() -> SavedMacro {
        var move = MacroStep(.moveMouse)
        move.varyingMouse = true
        move.mouseXMinimum = -2; move.mouseXMaximum = 2
        move.mouseYMinimum = -2; move.mouseYMaximum = 2
        var repeating = MacroStep(.repeatFor)
        repeating.varyingInterval = true
        repeating.mouseIntervalSeconds = 45; repeating.mouseIntervalMaximumSeconds = 95
        repeating.children = [move]
        return SavedMacro(name: "Mouse Jiggle", steps: [repeating])
    }

    var flattenedSteps: [MacroStep] { steps.flatMap { [$0] + ($0.kind == .repeatFor ? ($0.children ?? []) : []) } }
    var prefersStandalone: Bool {
        steps.contains { $0.kind == .mouseJiggle || ($0.kind == .repeatFor && ($0.children ?? []).contains { $0.kind == .moveMouse }) }
    }
    var migratingLegacyMouse: SavedMacro {
        var result = self
        result.steps = steps.map { step in
            guard step.kind == .mouseJiggle else { return step }
            var repeatStep = step; repeatStep.kind = .repeatFor
            var back = MacroStep(.moveMouse); back.mouseXMinimum = -1
            repeatStep.children = [.init(.moveMouse), .init(.delay, milliseconds: 50), back]
            return repeatStep
        }
        return result
    }
}

struct MacroDocument: Codable, Equatable {
    var schemaVersion: Int
    var macros: [SavedMacro]
    init(schemaVersion: Int? = nil, macros: [SavedMacro]) {
        self.schemaVersion = schemaVersion ?? (macros.contains { $0.steps.contains { [.moveMouse, .repeatFor].contains($0.kind) } } ? 3 :
            macros.contains { $0.steps.contains { $0.kind == .mouseJiggle } } ? 2 : 1)
        self.macros = macros
    }
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
    let program: Data
    let operations: [MacroOperation]
    let preview: [String]
    let layout: MacroLayout
    let target: TargetSystem
    init(operations: [MacroOperation], preview: [String], layout: MacroLayout, target: TargetSystem = .macOS) throws {
        self.program = try MacroProgram.encode(operations)
        self.operations = operations
        self.preview = preview
        self.layout = layout
        self.target = target
    }
    var bytes: Int { program.count }
    var hasMouse: Bool { operations.contains { $0.hasMouse } }
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
        var mouseTime = 0
        var identifiers = Set<UUID>()
        var nodes = 0
        var definitionBytes = 0
        func validateSteps(_ steps: [MacroStep], nested: Bool) throws -> Bool {
            guard !steps.isEmpty, steps.count <= 128 else { throw MacroError.invalid("Each sequence needs 1-128 steps.") }
            var hasOutput = false
            for step in steps {
                nodes += 1; definitionBytes += step.value.utf8.count
                guard nodes <= 512, definitionBytes <= maximumBytes,
                      identifiers.insert(step.id).inserted else { throw MacroError.invalid("Too many steps, duplicate IDs or oversized definitions.") }
                guard step.kind == .repeatFor || step.children?.isEmpty != false else {
                    throw MacroError.invalid("Only Repeat can contain child steps.")
                }
                switch step.kind {
                case .text:
                    try validateText(step.value, layout: macro.layout)
                    hasOutput = hasOutput || !step.value.isEmpty
                case .template:
                    try validateText(step.value, layout: macro.layout)
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
                case .mouseJiggle:
                    guard !nested, (1...86_400).contains(step.jiggleDuration), (1...3_600).contains(step.jiggleInterval),
                          mouseTime <= 86_400 - step.jiggleDuration else {
                        throw MacroError.invalid("Mouse Jiggle allows at most 24 hours total and intervals of 1-3600 seconds.")
                    }
                    mouseTime += step.jiggleDuration
                    hasOutput = true
                case .moveMouse:
                    guard (-127...127).contains(step.xMinimum), (-127...127).contains(step.xMaximum),
                          (-127...127).contains(step.yMinimum), (-127...127).contains(step.yMaximum),
                          step.xMinimum <= step.xMaximum, step.yMinimum <= step.yMaximum,
                          step.xMinimum != 0 || step.xMaximum != 0 || step.yMinimum != 0 || step.yMaximum != 0 else {
                        throw MacroError.invalid("Move Mouse needs ordered X/Y ranges within -127...127 and a nonzero movement.")
                    }
                    hasOutput = true
                case .repeatFor:
                    guard !nested, (1...86_400).contains(step.jiggleDuration),
                          (1...3_600).contains(step.jiggleInterval), step.intervalMaximum >= step.jiggleInterval,
                          step.intervalMaximum <= 3_600, mouseTime <= 86_400 - step.jiggleDuration else {
                        throw MacroError.invalid("Repeat permits 24 hours total, intervals of 1-3600 seconds, and no nesting.")
                    }
                    mouseTime += step.jiggleDuration
                    guard try validateSteps(step.children ?? [], nested: true) else { throw MacroError.invalid("Repeat needs an output action.") }
                    hasOutput = true
                }
            }
            return hasOutput
        }
        guard try validateSteps(macro.steps, nested: false), totalDelay <= 120_000 else {
            throw MacroError.invalid("A macro needs output and at most 120 seconds of explicit delays.")
        }
    }

    static func compile(_ macro: SavedMacro, context: MacroRunContext, limit: Int = maximumBytes) throws -> CompiledMacro {
        try validate(macro)
        var operations: [MacroOperation] = []
        var preview: [String] = []
        var encodedBytes = 6
        let capacity = min(limit, maximumBytes)
        func reserve(_ count: Int) throws {
            guard encodedBytes <= capacity, count <= capacity - encodedBytes else {
                throw MacroError.invalid("Expanded macro exceeds the connected device's capacity.")
            }
            encodedBytes += count
        }
        func compileSteps(_ steps: [MacroStep], indent: String = "") throws -> [MacroOperation] {
            var result: [MacroOperation] = []
            for step in steps {
                switch step.kind {
                case .text, .template:
                    let text = step.kind == .text ? step.value : try expand(step.value, context: context, layout: macro.layout)
                    try validateText(text, layout: macro.layout)
                    let normalized = text.precomposedStringWithCanonicalMapping
                        .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                    if !normalized.isEmpty { try reserve(5 + normalized.utf8.count); result.append(.text(normalized)) }
                    preview.append("\(indent)Text: \(normalized)")
                case .chord:
                    try reserve(4)
                    let key = try chord(step.value, target: macro.target)
                    result.append(key)
                    preview.append("\(indent)Key: \(step.value)")
                case .delay:
                    try reserve(5)
                    result.append(.delay(UInt32(step.milliseconds)))
                    preview.append("\(indent)Delay: \(step.milliseconds) ms")
                case .mouseJiggle:
                    try reserve(9)
                    result.append(.mouseJiggle(duration: UInt32(step.jiggleDuration) * 1_000,
                                                    interval: UInt32(step.jiggleInterval) * 1_000))
                    preview.append("Mouse Jiggle: \(step.summary); no clicks or keys")
                case .moveMouse:
                    try reserve(5)
                    result.append(.moveMouse(xMin: Int8(step.xMinimum), xMax: Int8(step.xMaximum),
                                             yMin: Int8(step.yMinimum), yMax: Int8(step.yMaximum)))
                    preview.append("\(indent)Move Mouse: \(step.summary)")
                case .repeatFor:
                    try reserve(19)
                    preview.append("\(indent)Repeat: \(step.summary)")
                    let body = try compileSteps(step.children ?? [], indent: indent + "  ")
                    result.append(.repeatFor(duration: UInt32(step.jiggleDuration) * 1_000,
                                             intervalMin: UInt32(step.jiggleInterval) * 1_000,
                                             intervalMax: UInt32(step.intervalMaximum) * 1_000, body: body))
                }
            }
            return result
        }
        operations = try compileSteps(macro.steps)
        let result = try CompiledMacro(operations: operations, preview: preview, layout: macro.layout, target: macro.target)
        guard result.bytes <= min(limit, maximumBytes) else {
            throw MacroError.invalid("Expanded macro exceeds the connected device's capacity.")
        }
        return result
    }

    static func validateText(_ text: String, layout: MacroLayout = .us) throws {
        guard text.utf8.count <= maximumBytes,
              text.precomposedStringWithCanonicalMapping.unicodeScalars.allSatisfy(layout.supports) else {
            throw MacroError.invalid("USB text supports ASCII, tabs and line breaks; Turkish letters require Turkish Q (experimental).")
        }
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

    private static func expand(_ template: String, context: MacroRunContext, layout: MacroLayout) throws -> String {
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
            try validateText(value, layout: layout)
            byteCount += value.utf8.count - match.range.length
            guard byteCount <= maximumBytes else { throw MacroError.invalid("Expanded template is too large.") }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    private static func chord(_ value: String, target: TargetSystem) throws -> MacroOperation {
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
        let code = MacroKey.special[key] ?? UInt16(key.lowercased().utf8.first!)
        let bits: [String: UInt8] = ["CTRL": 1, "SHIFT": 2, "ALT": 4, "WIN": 8]
        return .key(modifiers: modifiers.reduce(0) { $0 | bits[$1]! }, code: code)
    }
}
