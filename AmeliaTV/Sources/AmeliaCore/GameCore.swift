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

        // The game's own driving (auto-drive / lane guidance) is layered on top
        // of player input: auto channels apply at full authority, player steering
        // is scaled by the assist level.
        let throttle = max(input.throttle, autoThrottle)
        let brake = max(input.brake, autoBrake)

        if throttle > 0 { speed += accel * throttle * dt }
        if brake > 0 {
            speed -= (speed > 0.2 ? brakeForce : 7) * brake * dt
        }
        if throttle == 0 { speed -= (speed == 0 ? 0 : (speed > 0 ? 1.0 : -1.0)) * drag * dt }
        if abs(speed) < 0.05 { speed = 0 }
        speed = speed.clamped(to: -5 ... maxSpeed)

        // Steering scaled by assist authority, plus the game's auto-steer.
        let moveFactor = min(1.0, abs(speed) / 5.0)
        let steer = (input.steer * assistLevel.steeringAuthority + autoSteer).clamped(to: -1 ... 1)
        let turn = steer * 2.0 * moveFactor * (speed < 0 ? -1 : 1)
        var heading = bus.heading + turn * dt

        let velocity = Vec2.fromHeading(heading, length: speed * dt)
        let position = bus.position + velocity

        // Normalize heading to a stable range.
        heading = atan2(sin(heading), cos(heading))

        bus = BusState(position: position, heading: heading, speed: speed)
    }

    /// The game's own driving commands (Auto-Drive / lane guidance), applied at
    /// full authority on top of (assist-scaled) player input. Set by GameSession
    /// each tick; default 0 so the bus waits for the player.
    public var autoThrottle: Double = 0
    public var autoBrake: Double = 0
    public var autoSteer: Double = 0

    public func reset(to position: Vec2 = .zero, heading: Double = 0) {
        bus = BusState(position: position, heading: heading, speed: 0)
    }
}
