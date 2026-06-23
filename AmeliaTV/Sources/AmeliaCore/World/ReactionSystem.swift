import Foundation

/// What an onlooker does when the bus honks — the heart of "honk → the world
/// reacts." The *selection* lives in Core (pure, unit-tested); the renderer just
/// plays the matching animation. Reactions are spread across onlookers and change
/// per honk, so the street never reacts in unison.
public enum HonkReaction: String, CaseIterable, Sendable {
    case wave, hop, heart, spin, cheer
}

public struct ReactionSystem: Sendable {
    public init() {}

    /// A reaction for the onlooker with this stable index on this honk.
    /// Deterministic (so it's testable) but varied across the crowd and over time.
    public func reaction(forReactor index: Int, honkCount: Int = 0) -> HonkReaction {
        let all = HonkReaction.allCases
        let i = ((index * 7) + (honkCount * 3)) % all.count
        return all[(i + all.count) % all.count]
    }

    /// Whether an onlooker `distance` world-units from the bus is close enough to
    /// notice the honk and react.
    public func reacts(atDistance distance: Double, radius: Double = 400) -> Bool {
        distance <= radius
    }
}
