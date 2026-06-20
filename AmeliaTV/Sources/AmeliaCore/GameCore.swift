import Foundation

/// The top-level, rendering-agnostic game state + tick.
///
/// PHASE 1 SCOPE: this is the foundation skeleton — it owns the bus pose, the
/// current assist level, and a minimal driving integration so the render layer
/// has observable state to follow. The full EpisodeRunner / Navigation / Traffic
/// systems are Phase 2 backlog items (A2-03..A2-06) and intentionally NOT here.
///
/// The Core never imports RealityKit/SwiftUI; the renderer observes `bus` and the
/// app feeds `InputIntents` each frame. See docs/tvos/TECHNICAL_ARCHITECTURE.md.
public final class GameCore {

    /// Observable pose of the bus on the ground plane.
    public struct BusState: Equatable, Sendable {
        public var position: Vec2
        public var heading: Double   // radians, 0 = +x (matches drive/bus.js)
        public var speed: Double     // units/sec
        public init(position: Vec2 = .zero, heading: Double = 0, speed: Double = 0) {
            self.position = position
            self.heading = heading
            self.speed = speed
        }
    }

    public private(set) var bus = BusState()
    public var assistLevel: AssistLevel
    public var save: SaveSlot

    public init(save: SaveSlot = SaveSlot()) {
        self.save = save
        self.assistLevel = save.assistLevel
    }

    /// Advance the simulation by `dt` seconds given the latest input.
    /// Kid-friendly arcade model (ported in spirit from drive/bus.js): gentle
    /// acceleration, soft drag, capped speed, steering only while moving.
    public func tick(dt: Double, input: InputIntents) {
        guard dt > 0 else { return }

        let accel = 16.0, brakeForce = 28.0, drag = 3.2
        let maxSpeed = assistLevel.maxSpeed

        var speed = bus.speed

        // In Auto-Drive the bus rolls forward on its own; otherwise the player
        // supplies throttle.
        let throttle = assistLevel.autoDrives ? max(input.throttle, autoThrottle) : input.throttle

        if throttle > 0 { speed += accel * throttle * dt }
        if input.brake > 0 {
            speed -= (speed > 0.2 ? brakeForce : 7) * input.brake * dt
        }
        if throttle == 0 { speed -= (speed == 0 ? 0 : (speed > 0 ? 1.0 : -1.0)) * drag * dt }
        if abs(speed) < 0.05 { speed = 0 }
        speed = speed.clamped(to: -5 ... maxSpeed)

        // Steering scaled by assist authority, only meaningful while moving.
        let moveFactor = min(1.0, abs(speed) / 5.0)
        let steer = input.steer * assistLevel.steeringAuthority
        let turn = steer * 2.0 * moveFactor * (speed < 0 ? -1 : 1)
        var heading = bus.heading + turn * dt

        let velocity = Vec2.fromHeading(heading, length: speed * dt)
        let position = bus.position + velocity

        // Normalize heading to a stable range.
        heading = atan2(sin(heading), cos(heading))

        bus = BusState(position: position, heading: heading, speed: speed)
    }

    /// Whether the bus should auto-roll (Auto-Drive). Set by higher layers when
    /// a `driveTo`/story beat wants movement; defaults off so the bus waits.
    public var autoThrottle: Double = 0

    public func reset(to position: Vec2 = .zero, heading: Double = 0) {
        bus = BusState(position: position, heading: heading, speed: 0)
    }
}
