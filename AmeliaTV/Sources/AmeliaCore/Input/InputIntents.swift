import Foundation

/// Device-agnostic player intents.
///
/// The Game Core consumes ONLY this struct — it never knows whether the input
/// came from a Siri Remote or an MFi/PS/Xbox controller. The app's input
/// adapters (see App/Input/GameControllerInput.swift) translate hardware into
/// these intents. This is the boundary described in
/// docs/tvos/TECHNICAL_ARCHITECTURE.md ("Input model").
public struct InputIntents: Equatable, Sendable {
    /// Continuous steering, -1 (full left) ... +1 (full right).
    public var steer: Double
    /// Throttle, 0 ... 1.
    public var throttle: Double
    /// Brake, 0 ... 1.
    public var brake: Double
    /// A discrete left/right pick for `choice` beats and menu navigation.
    public var discreteTurn: DiscreteTurn
    /// Edge-triggered: the player pressed "honk" this frame.
    public var honkPressed: Bool
    /// Edge-triggered: confirm / select (menus, "Let's go!").
    public var confirmPressed: Bool
    /// Edge-triggered: back / cancel.
    public var backPressed: Bool

    public enum DiscreteTurn: Equatable, Sendable {
        case none, left, right
    }

    public init(
        steer: Double = 0,
        throttle: Double = 0,
        brake: Double = 0,
        discreteTurn: DiscreteTurn = .none,
        honkPressed: Bool = false,
        confirmPressed: Bool = false,
        backPressed: Bool = false
    ) {
        self.steer = steer.clamped(to: -1 ... 1)
        self.throttle = throttle.clamped(to: 0 ... 1)
        self.brake = brake.clamped(to: 0 ... 1)
        self.discreteTurn = discreteTurn
        self.honkPressed = honkPressed
        self.confirmPressed = confirmPressed
        self.backPressed = backPressed
    }

    public static let neutral = InputIntents()
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
