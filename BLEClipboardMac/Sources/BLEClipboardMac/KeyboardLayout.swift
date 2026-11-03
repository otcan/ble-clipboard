import Foundation

enum KeyboardLayout: String, Codable, CaseIterable, Identifiable {
    // Stable protocol layout IDs; append, never reorder.
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
    var wireID: UInt8 { UInt8(Self.allCases.firstIndex(of: self)!) }
    init?(wireID: UInt8) {
        guard Int(wireID) < Self.allCases.count else { return nil }
        self = Self.allCases[Int(wireID)]
    }

    var title: String {
        switch self {
        case .us: return "English (US)"
        case .turkishQ: return "Turkish Q (experimental)"
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

    func supports(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (32...126).contains(value) || [9, 10, 13].contains(value) { return true }
        return self == .turkishQ && Self.turkishLetters.contains(value)
    }

    private static let turkishLetters: Set<UInt32> = [
        0x00C7, 0x00E7, 0x011E, 0x011F, 0x0130, 0x0131,
        0x00D6, 0x00F6, 0x015E, 0x015F, 0x00DC, 0x00FC,
    ]
}
