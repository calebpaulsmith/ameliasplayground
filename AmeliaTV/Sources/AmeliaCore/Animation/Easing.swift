import Foundation

/// Tiny, GPU-free animation math used by the render layer to make motion feel
/// *alive* (ease and overshoot, don't snap). It lives in the Core on purpose, so
/// the math is unit-tested headlessly while the entity mutation stays in the app.
/// See docs/tvos/GAME_DESIGN.md §4a (Character Life & Charm).
public enum Easing {

    /// Frame-rate-independent exponential smoothing: eases `current` toward
    /// `target`. `rate` is responsiveness (higher = snappier). The trajectory is
    /// the same for a given elapsed time regardless of the step size, so it stays
    /// stable whether the render loop ticks at 60fps or stutters.
    public static func smoothed(_ current: Double, toward target: Double,
                                rate: Double, dt: Double) -> Double {
        guard dt > 0, rate > 0 else { return current }
        let t = 1 - exp(-rate * dt)
        return current + (target - current) * t
    }

    /// Linear interpolation, `t` clamped to 0...1.
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(max(t, 0), 1)
    }
}

/// A small dampable spring for squash / hop / overshoot motion — the secret to a
/// "boing" that feels playful rather than mechanical. Pure value type, integrated
/// each frame toward a `target`; `nudge` injects an impulse (a honk wiggle, a
/// happy hop). Defaults are underdamped for a gentle bounce.
///
/// Named `SpringValue` (not `Spring`) to avoid colliding with `SwiftUI.Spring`
/// in the render layer.
public struct SpringValue: Equatable, Sendable {
    public var value: Double
    public var velocity: Double
    public var stiffness: Double
    public var damping: Double

    public init(value: Double = 0, velocity: Double = 0,
                stiffness: Double = 180, damping: Double = 18) {
        self.value = value
        self.velocity = velocity
        self.stiffness = stiffness
        self.damping = damping
    }

    /// Advance toward `target` by `dt` (semi-implicit Euler; stable for sane dt).
    public mutating func step(toward target: Double, dt: Double) {
        guard dt > 0 else { return }
        let force = stiffness * (target - value) - damping * velocity
        velocity += force * dt
        value += velocity * dt
    }

    /// Kick the spring — e.g. a honk wiggle or a pickup hop.
    public mutating func nudge(_ impulse: Double) { velocity += impulse }
}
