import Foundation

/// All persistent player progress for one profile. Stored locally only — no
/// network, no accounts (see docs/tvos/PRODUCT_VISION.md privacy constraints).
public struct SaveSlot: Codable, Equatable, Sendable {
    public var name: String
    public var language: Language
    public var assistLevel: AssistLevel
    public var stars: Int
    public var stickers: [String]
    public var cosmetics: [String]
    public var completedEpisodes: [String]

    public init(
        name: String = "Amelia",
        language: Language = .en,
        assistLevel: AssistLevel = .auto,
        stars: Int = 0,
        stickers: [String] = [],
        cosmetics: [String] = [],
        completedEpisodes: [String] = []
    ) {
        self.name = name
        self.language = language
        self.assistLevel = assistLevel
        self.stars = stars
        self.stickers = stickers
        self.cosmetics = cosmetics
        self.completedEpisodes = completedEpisodes
    }

    public mutating func award(stars: Int) {
        self.stars += max(0, stars)
    }

    public mutating func grant(sticker id: String) {
        if !stickers.contains(id) { stickers.append(id) }
    }

    public mutating func markComplete(episode id: String) {
        if !completedEpisodes.contains(id) { completedEpisodes.append(id) }
    }

    public func hasCompleted(episode id: String) -> Bool {
        completedEpisodes.contains(id)
    }
}
