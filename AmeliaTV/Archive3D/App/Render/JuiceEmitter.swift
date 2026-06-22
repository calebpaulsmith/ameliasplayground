import Foundation

#if canImport(RealityKit)
import RealityKit

#if canImport(UIKit)
import UIKit
#endif

/// A tiny, GPU-free particle burster built from primitive entities — the project
/// uses no `ParticleEmitterComponent` (clouds, birds and the bus springs are all
/// hand-animated), so juice stays in the same house style (CL-04, GAME_DESIGN §4a).
///
/// One fixed pool of small entities is recycled: `burst` launches a few with
/// velocities, `update` integrates + shrinks them over a short life, then parks
/// them back in the pool. Render-only; observes nothing from the Core.
@MainActor
final class JuiceEmitter {
    /// What a burst *feels* like: a star/collectible sparkle, a love-y heart puff
    /// (pickup/honk), or a dusty kick (braking / rolling fast).
    enum Kind { case sparkle, heart, dust }

    let root = Entity()

    private final class Particle {
        let node: ModelEntity
        var vel: SIMD3<Float> = .zero
        var life: Float = 0          // seconds remaining (≤ 0 ⇒ idle in the pool)
        var maxLife: Float = 1
        var size: Float = 0.12
        var spin: Float = 0
        init(_ node: ModelEntity) { self.node = node }
    }

    private var pool: [Particle] = []
    private let gravity: Float = -3.2

    init(capacity: Int = 72) {
        for _ in 0..<capacity {
            let node = ModelLibrary.placeholderBox(color: .white, size: [1, 1, 1])
            node.isEnabled = false
            node.scale = .zero
            root.addChild(node)
            pool.append(Particle(node))
        }
    }

    /// Launch a small burst from `at`, fanning upward and outward. Cheap: it only
    /// wakes already-allocated idle particles, never creates entities at runtime.
    func burst(at p: SIMD3<Float>, kind: Kind, count: Int = 10) {
        let color: PlatformColor
        let size: Float, up: Float, spread: Float
        switch kind {
        case .sparkle: color = PlatformColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1); size = 0.13; up = 2.7; spread = 1.9
        case .heart:   color = PlatformColor(red: 1.0, green: 0.46, blue: 0.62, alpha: 1); size = 0.17; up = 2.3; spread = 1.0
        case .dust:    color = PlatformColor(white: 0.82, alpha: 1);                       size = 0.20; up = 0.8; spread = 1.6
        }

        var launched = 0
        for particle in pool where particle.life <= 0 {
            if launched >= count { break }
            launched += 1
            particle.node.isEnabled = true
            particle.node.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
            particle.node.position = p
            particle.maxLife = Float.random(in: 0.55...1.0)
            particle.life = particle.maxLife
            particle.size = size * Float.random(in: 0.7...1.2)
            particle.spin = 0
            let ang = Float.random(in: 0 ..< (2 * Float.pi))
            let r = Float.random(in: 0...spread)
            particle.vel = [cos(ang) * r, up * Float.random(in: 0.7...1.2), sin(ang) * r]
        }
    }

    /// Integrate every live particle: gravity + drag, shrink toward death, gentle
    /// tumble. Idle particles (life ≤ 0) are skipped, so this stays cheap.
    func update(dt: Float) {
        for particle in pool where particle.life > 0 {
            particle.life -= dt
            if particle.life <= 0 {
                particle.node.isEnabled = false
                particle.node.scale = .zero
                continue
            }
            particle.vel.y += gravity * dt
            particle.vel *= max(0, 1 - 1.4 * dt)               // air drag
            particle.node.position += particle.vel * dt
            let k = particle.life / particle.maxLife            // 1 → 0
            let s = particle.size * (0.25 + 0.75 * k)           // shrink as it fades
            particle.node.scale = [s, s, s]
            particle.spin += dt * 7
            particle.node.orientation = simd_quatf(angle: particle.spin, axis: [0.3, 1, 0.15])
        }
    }
}
#endif
