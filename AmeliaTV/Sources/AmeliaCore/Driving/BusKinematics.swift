import Foundation

/// Simple top-down vehicle kinematics for the bus (and other cars). Pure Core,
/// unit-tested without a GPU: throttle changes speed, steer changes heading,
/// position integrates forward along the heading. This is **free steering**;
/// `AssistLevel` scales the `throttle`/`steer` inputs upstream (auto-drive can
/// supply them, the child can, or a controller can).
public struct BusKinematics: Sendable, Equatable {
    public var position: Vec2
    public var heading: Double      // radians, 0 = +x (matches Vec2.heading)
    public var speed: Double        // world units / second

    public var maxSpeed: Double
    public var accel: Double
    public var turnRate: Double     // radians/sec at full steer & full motion
    public var drag: Double         // deceleration when coasting

    public init(position: Vec2 = .zero,
                heading: Double = 0,
                speed: Double = 0,
                maxSpeed: Double = 260,
                accel: Double = 340,
                turnRate: Double = 2.6,
                drag: Double = 140) {
        self.position = position
        self.heading = heading
        self.speed = speed
        self.maxSpeed = maxSpeed
        self.accel = accel
        self.turnRate = turnRate
        self.drag = drag
    }

    /// Advance by `dt` seconds. `throttle` and `steer` are clamped to [-1, 1];
    /// positive `steer` turns toward increasing heading.
    public mutating func update(throttle: Double, steer: Double, dt: Double) {
        guard dt > 0 else { return }
        let th = max(-1, min(1, throttle))
        let st = max(-1, min(1, steer))

        speed += th * accel * dt
        if th == 0 { speed = max(0, speed - drag * dt) }   // coast to a stop
        speed = max(0, min(maxSpeed, speed))

        // Steering scales with motion so a parked bus doesn't pirouette.
        let motion = min(1, speed / 60)
        heading += st * turnRate * motion * dt

        position = position + Vec2.fromHeading(heading, length: speed * dt)
    }

    /// Steering value in [-1, 1] that aims the vehicle at `target` — used by the
    /// demo attract-drive and (later) auto-drive.
    public func steer(toward target: Vec2) -> Double {
        let desired = (target - position).heading
        var diff = desired - heading
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return max(-1, min(1, diff / 0.6))
    }
}
