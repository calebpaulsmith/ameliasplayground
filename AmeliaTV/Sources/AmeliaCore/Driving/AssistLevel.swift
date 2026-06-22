import Foundation

/// How much driving the player must do vs. how much the game does for them.
/// The single most important child-UX knob (see docs/tvos/GAME_DESIGN.md §6).
public enum AssistLevel: String, Codable, CaseIterable, Sendable {
    /// Youngest / Siri-Remote default. Amelia follows the route automatically;
    /// the player handles the fun decisions (GO, STOP, left/right, honk).
    case auto
    /// ~5-6 / parent default. The player steers, but strong lane guidance keeps
    /// the bus on the road; it can't really crash.
    case assisted
    /// Parent / Free Drive. Looser assist, full analog steering.
    case free

    /// A sensible default given the active input device.
    public static func recommended(for device: InputDeviceKind) -> AssistLevel {
        switch device {
        case .siriRemote: return .auto
        case .controller: return .assisted
        }
    }

    /// Whether the driving model should auto-advance the bus along the route.
    public var autoDrives: Bool { self == .auto }

    /// Fraction of player steering that is applied (the rest is lane guidance).
    public var steeringAuthority: Double {
        switch self {
        case .auto: return 0.0
        case .assisted: return 0.6
        case .free: return 1.0
        }
    }

    /// Top speed cap (game units/sec), kept calm for young children.
    public var maxSpeed: Double {
        switch self {
        case .auto: return 11     // calm, but enough to tour the whole town without dragging
        case .assisted: return 14
        case .free: return 17
        }
    }
}

public enum InputDeviceKind: String, Codable, Sendable {
    case siriRemote
    case controller
}
