import Foundation

/// The "Quick Stop!" challenge (PLAN_2D CH-01): a ball rolls across the street and
/// the bus must **brake in time**. A reaction meter drains while it runs; stopping
/// before it empties scores points (more for stopping sooner). **No harsh
/// failure** — missing just re-arms for another try, never a crash or penalty.
///
/// Pure Core so the timing/scoring is unit-tested without a GPU; the scene renders
/// the ball, the meter, and the reward.
public struct QuickStopChallenge: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case idle, running, success, missed
    }

    public private(set) var state: State = .idle
    /// 1 → 0 while running (the draining reaction meter).
    public private(set) var meter: Double = 1
    public private(set) var score: Int = 0

    public let duration: Double      // seconds the meter takes to drain
    public let stopSpeed: Double     // at/below this world speed the bus is "stopped"

    public init(duration: Double = 2.2, stopSpeed: Double = 8) {
        self.duration = duration
        self.stopSpeed = stopSpeed
    }

    /// Begin the challenge (ball starts crossing).
    public mutating func arm() {
        state = .running
        meter = 1
        score = 0
    }

    /// Advance while running. `busSpeed` is world units/second.
    public mutating func update(dt: Double, busSpeed: Double) {
        guard state == .running, dt > 0 else { return }
        if busSpeed <= stopSpeed {
            // Stopped in time — more meter left means a quicker stop, more points.
            score = Int((meter * 100).rounded())
            state = .success
            return
        }
        meter = max(0, meter - dt / duration)
        if meter <= 0 { state = .missed }
    }

    /// Back to idle (e.g. after the reward, or to retry a miss).
    public mutating func reset() {
        state = .idle
        meter = 1
    }
}
