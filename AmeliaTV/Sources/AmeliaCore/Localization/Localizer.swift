import Foundation

/// The two languages shipped in v1. Bilingual is a hard constraint
/// (see docs/tvos/PRODUCT_VISION.md): every player-facing line exists in both.
public enum Language: String, Codable, CaseIterable, Sendable {
    case en
    case es

    public var displayName: String {
        switch self {
        case .en: return "English"
        case .es: return "Español"
        }
    }
}

/// Resolves a string id + language into a line, with `{var}` substitution.
/// Mirrors the prototype's drive/i18n.js `t()` but data-driven (strings loaded
/// from bundled JSON rather than hardcoded).
public struct Localizer: Sendable {
    /// id -> (language -> text)
    private let table: [String: [String: String]]

    public init(table: [String: [String: String]]) {
        self.table = table
    }

    /// Returns the localized line for `id`, falling back to English, then the id
    /// itself, then performing `{name}`-style variable substitution.
    public func string(_ id: String, _ language: Language, vars: [String: String] = [:]) -> String {
        let entry = table[id]
        var line = entry?[language.rawValue] ?? entry?[Language.en.rawValue] ?? id
        for (key, value) in vars {
            line = line.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return line
    }

    public func hasTranslation(_ id: String, _ language: Language) -> Bool {
        guard let entry = table[id], let value = entry[language.rawValue] else { return false }
        return !value.isEmpty
    }

    public var ids: [String] { Array(table.keys) }
}
