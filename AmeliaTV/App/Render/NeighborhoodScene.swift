import Foundation

#if canImport(RealityKit)
import RealityKit
import AmeliaCore

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Builds the cozy neighborhood the bus drives through, entirely from the
/// data-driven content (`places.json` / `lights.json`) so the layout stays in
/// versioned data, not code (A2-08). Everything is an **original** placeholder
/// in a friendly, brightly-coloured genre style — no third-party likenesses
/// (docs/tvos/RISKS_AND_DECISIONS.md D-IP-1). USDZ art can be swapped in later
/// by id via `ModelLibrary` without touching this file.
///
/// Each `place.kind` is its own little **district** with a signature **landmark**,
/// a coloured ground "pad", and matching set-dressing, so the world reads as a
/// real town with a sense of place — the park, the school with its clock tower &
/// flag, the market with striped awnings, and the seaside with a striped
/// lighthouse — all linked by a tree-lined loop road.
@MainActor
final class NeighborhoodScene {
    let root = Entity()

    /// Live traffic-light lamps, keyed by light id, so the engine can light the
    /// active lamp each frame.
    private var lamps: [String: Lamps] = [:]

    private struct Lamps { let red: ModelEntity; let yellow: ModelEntity; let green: ModelEntity }

    /// Maps Game Core ground units to scene meters (matches the engine's bus).
    private let scale: Float

    init(content: GameContent, scale: Float) {
        self.scale = scale
        buildGround()
        let segments = routeLoop(content: content)
        buildRoads(segments)
        buildScenery(along: segments)
        for place in content.places { buildPlace(place) }
        for light in content.lights { buildLight(light) }
        buildVehicles(content)
        buildClouds()
    }

    /// Parks the Rescue Team vehicles near their home places, spreading multiple
    /// vehicles at the same place so they don't overlap.
    private func buildVehicles(_ content: GameContent) {
        var perPlace: [String: Int] = [:]
        for v in content.vehicles {
            guard let place = content.places.first(where: { $0.id == v.homePlace }) else { continue }
            let n = perPlace[v.homePlace, default: 0]
            perPlace[v.homePlace] = n + 1
            let color = ModelLibrary.color(hex: v.color) ?? PlatformColor(white: 0.8, alpha: 1)
            let node = ModelLibrary.vehicle(modelRef: v.modelRef, role: v.role, color: color)
            var p = scenePos(place.position.vec, y: 0)
            p.x -= 3.0                              // sit off to one side
            p.z += Float(n) * 2.8 - 1.4            // line them up
            node.position = p
            node.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])  // face the road
            root.addChild(node)
        }
    }

    /// Lights the lamp matching each light's state and dims the others.
    func updateLights(_ states: [String: TrafficLight.State]) {
        for (id, l) in lamps {
            let state = states[id] ?? .green
            set(l.red, on: state == .red, lit: Self.redOn, off: Self.redOff)
            set(l.yellow, on: state == .yellow, lit: Self.yellowOn, off: Self.yellowOff)
            set(l.green, on: state == .green, lit: Self.greenOn, off: Self.greenOff)
        }
    }

    // MARK: - World → scene helpers

    private func scenePos(_ v: Vec2, y: Float) -> SIMD3<Float> {
        [Float(v.x) * scale, y, Float(v.z) * scale]
    }

    // MARK: - Small primitive helpers (keep the builders readable)

    private func col(_ r: Double, _ g: Double, _ b: Double) -> PlatformColor {
        PlatformColor(red: r, green: g, blue: b, alpha: 1)
    }

    private func block(_ color: PlatformColor, _ size: SIMD3<Float>,
                       at p: SIMD3<Float>, yaw: Float = 0, roll: Float = 0) -> ModelEntity {
        let e = ModelLibrary.placeholderBox(color: color, size: size)
        e.position = p
        if yaw != 0 || roll != 0 {
            e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: roll, axis: [0, 0, 1])
        }
        return e
    }

    private func ball(_ color: PlatformColor, _ r: Float,
                      at p: SIMD3<Float>, scale s: SIMD3<Float> = [1, 1, 1]) -> ModelEntity {
        let e = ModelLibrary.sphere(radius: r, color: color)
        e.position = p
        e.scale = s
        return e
    }

    /// A soft round ground pad (a flattened disc) marking a district's footprint.
    private func disc(_ color: PlatformColor, radius: Float, at p: SIMD3<Float>) -> ModelEntity {
        ball(color, radius, at: [p.x, 0.02, p.z], scale: [1, 0.03, 1])
    }

    // MARK: - Ground

    private func buildGround() {
        let ground = ModelLibrary.ground(size: 320,
            color: PlatformColor(red: 0.52, green: 0.80, blue: 0.47, alpha: 1))
        ground.position = [0, 0, 0]
        root.addChild(ground)
    }

    // MARK: - Roads (a loop touring every district) + scenery

    /// An ordered tour of the places so the streets form one connected loop
    /// through every district — strong "travelling through town" feel even though
    /// the slice itself only drives part of it.
    private func routeLoop(content: GameContent) -> [(Vec2, Vec2)] {
        let order = ["garage", "stopA", "park", "school", "market", "beach"]
        let pts: [Vec2] = order.compactMap { id in
            content.places.first { $0.id == id }?.position.vec
        }
        guard pts.count > 1 else { return [] }
        var segs: [(Vec2, Vec2)] = []
        for i in 0..<pts.count { segs.append((pts[i], pts[(i + 1) % pts.count])) }
        return segs
    }

    private func buildRoads(_ segments: [(Vec2, Vec2)]) {
        for (a, b) in segments { road(from: a, to: b) }
    }

    private func road(from a: Vec2, to b: Vec2) {
        let d = b - a
        let len = Float(d.length) * scale
        guard len > 0.01 else { return }
        let angle = Float(atan2(d.z, d.x))
        let mid = (a + b) * 0.5
        // A pale "sidewalk" slab under a darker carriageway, with a dashed centre line.
        let sidewalk = block(col(0.78, 0.77, 0.73), [len + 0.6, 0.03, 2.4],
                             at: scenePos(mid, y: 0.025), yaw: -angle)
        root.addChild(sidewalk)
        let strip = block(col(0.27, 0.28, 0.30), [len, 0.04, 1.5],
                          at: scenePos(mid, y: 0.035), yaw: -angle)
        root.addChild(strip)
        // Dashed centre line.
        let dashes = max(1, Int(len / 1.4))
        for i in 0..<dashes where i % 2 == 0 {
            let t = (Float(i) + 0.5) / Float(dashes)
            let dash = block(col(0.95, 0.86, 0.45), [0.5, 0.05, 0.1],
                             at: scenePos(a + d * Double(t), y: 0.045), yaw: -angle)
            root.addChild(dash)
        }
    }

    /// Lines the streets with lamp posts and a varied ribbon of trees so the world
    /// feels lived-in between the landmarks (deterministic placement).
    private func buildScenery(along segments: [(Vec2, Vec2)]) {
        for (idx, seg) in segments.enumerated() {
            let (a, b) = seg
            let d = b - a
            let len = d.length
            guard len > 6 else { continue }
            let inv = 1.0 / len
            let perp = Vec2(-d.z * inv, d.x * inv)          // unit perpendicular
            let n = max(1, Int(len / 20))
            for k in 1...n {
                let t = Double(k) / Double(n + 1)
                let on = a + d * t
                let side: Double = (k % 2 == 0) ? 1 : -1
                // A lamp post right at the kerb.
                lampPost(at: scenePos(on + perp * (2.4 * side), y: 0))
                // A tree set a little further back; vary the species.
                let treeAt = scenePos(on + perp * (5.0 * side), y: 0)
                switch (idx + k) % 3 {
                case 0: roundTree(at: treeAt, leaf: col(0.30, 0.66, 0.32))
                case 1: roundTree(at: treeAt, leaf: col(0.40, 0.70, 0.30), s: 1.2)
                default: pineTree(at: treeAt)
                }
            }
        }
    }

    // MARK: - Reusable set pieces

    private func lampPost(at p: SIMD3<Float>) {
        root.addChild(block(col(0.25, 0.26, 0.28), [0.12, 2.2, 0.12], at: [p.x, 1.1, p.z]))
        root.addChild(block(col(0.25, 0.26, 0.28), [0.5, 0.1, 0.12], at: [p.x + 0.2, 2.1, p.z]))
        root.addChild(ball(col(1.0, 0.93, 0.6), 0.16, at: [p.x + 0.4, 2.05, p.z]))
    }

    private func roundTree(at p: SIMD3<Float>, leaf: PlatformColor, s: Float = 1) {
        root.addChild(block(col(0.52, 0.36, 0.22), [0.22 * s, 0.9 * s, 0.22 * s], at: [p.x, 0.45 * s, p.z]))
        root.addChild(ball(leaf, 0.62 * s, at: [p.x, 1.15 * s, p.z]))
        root.addChild(ball(leaf, 0.46 * s, at: [p.x + 0.26 * s, 1.5 * s, p.z - 0.1 * s]))
        root.addChild(ball(leaf, 0.4 * s, at: [p.x - 0.22 * s, 1.45 * s, p.z + 0.14 * s]))
    }

    private func pineTree(at p: SIMD3<Float>, s: Float = 1) {
        root.addChild(block(col(0.5, 0.34, 0.2), [0.2 * s, 0.7 * s, 0.2 * s], at: [p.x, 0.35 * s, p.z]))
        let green = col(0.20, 0.55, 0.30)
        root.addChild(ball(green, 0.6 * s, at: [p.x, 0.95 * s, p.z], scale: [1, 1.15, 1]))
        root.addChild(ball(green, 0.46 * s, at: [p.x, 1.5 * s, p.z], scale: [1, 1.2, 1]))
        root.addChild(ball(green, 0.32 * s, at: [p.x, 2.0 * s, p.z], scale: [1, 1.3, 1]))
    }

    /// A leaning palm for the seaside.
    private func palmTree(into g: Entity, at p: SIMD3<Float>, s: Float = 1) {
        g.addChild(block(col(0.62, 0.48, 0.28), [0.18 * s, 1.3 * s, 0.18 * s], at: [p.x, 0.65 * s, p.z], roll: 0.12))
        g.addChild(block(col(0.62, 0.48, 0.28), [0.15 * s, 0.9 * s, 0.15 * s], at: [p.x + 0.22 * s, 1.6 * s, p.z], roll: 0.28))
        let frond = col(0.22, 0.62, 0.34)
        let crown = SIMD3<Float>(p.x + 0.42 * s, 2.05 * s, p.z)
        for i in 0..<6 {
            let a = Float(i) / 6 * .pi * 2
            let leaf = ModelLibrary.placeholderBox(color: frond, size: [1.0 * s, 0.06 * s, 0.26 * s])
            leaf.position = [crown.x + cos(a) * 0.5 * s, crown.y, crown.z + sin(a) * 0.5 * s]
            leaf.orientation = simd_quatf(angle: -a, axis: [0, 1, 0]) * simd_quatf(angle: 0.25, axis: [0, 0, 1])
            g.addChild(leaf)
        }
        g.addChild(ball(col(0.45, 0.3, 0.18), 0.1 * s, at: [crown.x, crown.y - 0.12 * s, crown.z]))
    }

    /// A grid of little windows proud of a facade at +z.
    private func windows(into g: Entity, count: Int, y: Float, faceZ: Float, spacing: Float) {
        let start = -Float(count - 1) / 2 * spacing
        for i in 0..<count {
            g.addChild(block(col(0.75, 0.90, 1.0), [0.45, 0.55, 0.06],
                             at: [start + Float(i) * spacing, y, faceZ]))
        }
    }

    // MARK: - Places (each its own district + landmark)

    private func buildPlace(_ place: Place) {
        let tint = ModelLibrary.color(hex: place.beaconColor)
            ?? PlatformColor(white: 0.8, alpha: 1)
        let group = Entity()
        group.position = scenePos(place.position.vec, y: 0)

        switch place.kind {
        case "busStop": padAndBuild(group, pad: col(0.74, 0.73, 0.70)) { self.buildBusStop(into: $0, tint: tint) }
        case "park":    padAndBuild(group, pad: col(0.44, 0.76, 0.42)) { self.buildPark(into: $0) }
        case "garage":  padAndBuild(group, pad: col(0.70, 0.70, 0.72)) { self.buildGarage(into: $0, tint: tint) }
        case "school":  padAndBuild(group, pad: col(0.62, 0.78, 0.52)) { self.buildSchool(into: $0, tint: tint) }
        case "market":  padAndBuild(group, pad: col(0.80, 0.74, 0.60)) { self.buildMarket(into: $0, tint: tint) }
        case "beach":   buildBeach(into: group, tint: tint)
        default:        padAndBuild(group, pad: col(0.72, 0.72, 0.70)) { self.buildBuilding(into: $0, tint: tint) }
        }
        root.addChild(group)
    }

    private func padAndBuild(_ group: Entity, pad: PlatformColor, _ build: (Entity) -> Void) {
        group.addChild(disc(pad, radius: 4.2, at: [0, 0, 0]))
        build(group)
    }

    /// A generic friendly storefront: a coloured box with a contrasting roof.
    private func buildBuilding(into group: Entity, tint: PlatformColor) {
        let base = ModelLibrary.placeholderBox(color: tint, size: [2.6, 2.0, 2.6])
        base.position = [0, 1.0, 0]
        group.addChild(base)
        group.addChild(block(col(0.95, 0.95, 0.95), [2.9, 0.4, 2.9], at: [0, 2.1, 0]))
        windows(into: group, count: 2, y: 1.1, faceZ: 1.32, spacing: 0.9)
    }

    /// A bus-stop shelter: a flat roof on two posts, a bench, a tall striped sign,
    /// and a little timetable board — a proper place to wait.
    private func buildBusStop(into group: Entity, tint: PlatformColor) {
        group.addChild(block(tint, [2.4, 0.18, 1.2], at: [0, 1.7, 0]))
        for x in [Float(-1.0), 1.0] {
            group.addChild(block(col(0.85, 0.85, 0.85), [0.14, 1.7, 0.14], at: [x, 0.85, 0.5]))
        }
        // Bench under the shelter.
        group.addChild(block(col(0.62, 0.43, 0.28), [1.6, 0.1, 0.4], at: [0, 0.5, 0.1]))
        group.addChild(block(col(0.62, 0.43, 0.28), [1.6, 0.5, 0.1], at: [0, 0.7, -0.1]))
        // A tall striped sign pole with a round sign.
        group.addChild(block(col(0.9, 0.9, 0.92), [0.12, 2.6, 0.12], at: [1.5, 1.3, 0.5]))
        group.addChild(block(col(0.90, 0.24, 0.22), [0.14, 0.5, 0.14], at: [1.5, 1.0, 0.5]))
        let sign = ModelLibrary.sphere(radius: 0.34, color: tint)
        sign.position = [1.5, 2.7, 0.5]
        group.addChild(sign)
        group.addChild(block(.white, [0.34, 0.34, 0.04], at: [1.5, 2.7, 0.86]))
    }

    /// A leafy park: a grassy mound, a blue pond, flowers, a slide and swings, and
    /// a little tiered fountain as the centrepiece landmark.
    private func buildPark(into group: Entity) {
        let lawn = ball(col(0.36, 0.72, 0.36), 1.7, at: [0, 0, 0], scale: [1, 0.28, 1])
        group.addChild(lawn)
        // Pond.
        group.addChild(ball(col(0.32, 0.62, 0.85), 1.0, at: [-2.4, 0.04, 1.6], scale: [1.4, 0.04, 1]))
        // Trees + flowers around the edge.
        for o in [SIMD2<Float>(-1.6, -1.4), [1.7, -1.0], [1.2, 1.7]] {
            group.addChild(block(col(0.55, 0.38, 0.24), [0.22, 0.9, 0.22], at: [o.x, 0.45, o.y]))
            group.addChild(ball(col(0.30, 0.66, 0.32), 0.7, at: [o.x, 1.3, o.y]))
        }
        for f in [SIMD2<Float>(0.8, -1.6), [-1.2, 0.2], [2.2, 0.6]] {
            let petal = [col(0.96, 0.4, 0.5), col(0.98, 0.8, 0.3), col(0.7, 0.55, 0.95)].randomElement()!
            group.addChild(ball(petal, 0.12, at: [f.x, 0.34, f.y]))
        }
        // Playground: slide + swing set.
        group.addChild(block(col(0.95, 0.55, 0.25), [0.5, 0.06, 1.4], at: [2.6, 0.6, -1.6], roll: 0.5))
        group.addChild(block(col(0.85, 0.85, 0.88), [0.1, 1.0, 0.1], at: [3.0, 0.5, -1.6]))
        group.addChild(block(col(0.3, 0.6, 0.85), [0.1, 1.1, 1.6], at: [-2.6, 0.55, -1.4]))
        for sx in [Float(-2.9), -2.3] {
            group.addChild(block(col(0.95, 0.85, 0.3), [0.4, 0.06, 0.3], at: [sx, 0.3, -1.4]))
        }
        // Centrepiece fountain (landmark), set back so the arriving bus doesn't
        // park on top of it.
        let fx: Float = -0.4, fz: Float = -2.6
        group.addChild(ball(col(0.86, 0.86, 0.9), 0.9, at: [fx, 0.1, fz], scale: [1, 0.22, 1]))
        group.addChild(ball(col(0.40, 0.72, 0.92), 0.7, at: [fx, 0.18, fz], scale: [1, 0.12, 1]))
        group.addChild(block(col(0.86, 0.86, 0.9), [0.2, 0.8, 0.2], at: [fx, 0.5, fz]))
        group.addChild(ball(col(0.55, 0.8, 0.95), 0.34, at: [fx, 1.0, fz], scale: [1, 1.3, 1]))
    }

    /// The home garage: a warm workshop with a pitched roof, an open door, a
    /// chimney, a fuel pump and a hanging sign.
    private func buildGarage(into group: Entity, tint: PlatformColor) {
        group.addChild(block(tint, [3.4, 2.4, 2.8], at: [0, 1.2, 0]))
        group.addChild(block(col(0.86, 0.36, 0.30), [3.7, 0.4, 3.1], at: [0, 2.5, 0]))
        // Pitched ridge.
        group.addChild(block(col(0.78, 0.30, 0.26), [3.7, 0.4, 1.0], at: [0, 2.8, 0], roll: 0))
        group.addChild(block(col(0.18, 0.18, 0.2), [1.8, 1.6, 0.1], at: [0, 0.8, 1.41]))
        // Chimney with a puff.
        group.addChild(block(col(0.7, 0.4, 0.34), [0.4, 0.9, 0.4], at: [1.1, 3.0, -0.6]))
        group.addChild(ball(.white, 0.3, at: [1.1, 3.7, -0.6]))
        // Fuel pump.
        group.addChild(block(col(0.9, 0.3, 0.3), [0.4, 1.0, 0.4], at: [2.2, 0.5, 1.0]))
        group.addChild(block(col(0.2, 0.2, 0.22), [0.3, 0.3, 0.05], at: [2.2, 0.9, 1.22]))
        // Hanging sign.
        group.addChild(block(col(0.55, 0.38, 0.24), [0.12, 0.7, 0.12], at: [-1.9, 2.2, 1.3]))
        group.addChild(block(col(0.98, 0.82, 0.35), [1.0, 0.5, 0.1], at: [-1.4, 2.0, 1.3]))
    }

    /// The school: a brick building with rows of windows, a pitched roof, a big
    /// clock face, and a flag pole flying a flag — its landmark on the skyline.
    private func buildSchool(into group: Entity, tint: PlatformColor) {
        group.addChild(block(col(0.86, 0.52, 0.40), [4.0, 2.6, 2.6], at: [0, 1.3, 0]))
        group.addChild(block(col(0.55, 0.30, 0.26), [4.4, 0.4, 3.0], at: [0, 2.7, 0]))
        // Door.
        group.addChild(block(col(0.45, 0.28, 0.2), [0.9, 1.4, 0.1], at: [0, 0.7, 1.31]))
        windows(into: group, count: 3, y: 1.6, faceZ: 1.31, spacing: 1.1)
        // Clock tower (landmark).
        group.addChild(block(tint, [1.2, 3.6, 1.2], at: [1.6, 1.8, 0]))
        group.addChild(block(col(0.55, 0.30, 0.26), [1.5, 0.5, 1.5], at: [1.6, 3.9, 0]))
        group.addChild(ball(col(0.95, 0.5, 0.3), 0.5, at: [1.6, 4.3, 0], scale: [1, 1.1, 1]))
        group.addChild(ball(.white, 0.34, at: [1.6, 2.8, 0.62], scale: [1, 1, 0.3]))
        group.addChild(block(col(0.1, 0.1, 0.12), [0.04, 0.26, 0.03], at: [1.6, 2.86, 0.7]))
        group.addChild(block(col(0.1, 0.1, 0.12), [0.18, 0.03, 0.03], at: [1.66, 2.8, 0.7]))
        // Flag pole flying a flag.
        group.addChild(block(col(0.9, 0.9, 0.92), [0.1, 3.2, 0.1], at: [-1.8, 1.6, 0.8]))
        group.addChild(block(col(0.2, 0.55, 0.85), [0.9, 0.6, 0.04], at: [-1.35, 3.0, 0.8]))
    }

    /// The market: a row of stalls with bright striped awnings, crates of produce,
    /// and a welcome arch as the entrance landmark.
    private func buildMarket(into group: Entity, tint: PlatformColor) {
        let awnings = [col(0.90, 0.30, 0.30), col(0.30, 0.65, 0.90), col(0.95, 0.75, 0.25)]
        for (i, awn) in awnings.enumerated() {
            let x = Float(i) * 2.0 - 2.0
            // Counter + posts + awning.
            group.addChild(block(col(0.6, 0.42, 0.28), [1.6, 0.7, 1.0], at: [x, 0.45, 0]))
            for px in [x - 0.7, x + 0.7] {
                group.addChild(block(col(0.85, 0.85, 0.85), [0.1, 1.6, 0.1], at: [px, 0.8, -0.4]))
            }
            group.addChild(block(awn, [1.8, 0.16, 1.1], at: [x, 1.7, -0.1], roll: 0.18))
            group.addChild(block(.white, [1.8, 0.16, 0.2], at: [x, 1.62, 0.42], roll: 0.18))
            // Produce.
            let produce = [col(0.95, 0.4, 0.3), col(0.98, 0.75, 0.2), col(0.5, 0.8, 0.35)][i % 3]
            for dz in [Float(-0.2), 0.2] {
                group.addChild(ball(produce, 0.16, at: [x - 0.2, 0.9, dz]))
                group.addChild(ball(produce, 0.16, at: [x + 0.2, 0.9, dz]))
            }
        }
        // Welcome arch (landmark).
        for ax in [Float(-3.4), 3.4] {
            group.addChild(block(tint, [0.4, 3.0, 0.4], at: [ax, 1.5, 1.8]))
        }
        group.addChild(block(tint, [7.2, 0.5, 0.5], at: [0, 3.1, 1.8]))
        group.addChild(block(col(0.98, 0.95, 0.85), [3.0, 0.7, 0.1], at: [0, 3.1, 2.06]))
    }

    /// The seaside: a sandy shore meeting blue water, a striped lighthouse landmark,
    /// leaning palms, beach umbrellas and a short wooden pier.
    private func buildBeach(into group: Entity, tint: PlatformColor) {
        // Sand pad + the sea beside it.
        group.addChild(disc(col(0.93, 0.86, 0.62), radius: 4.6, at: [0, 0, 0]))
        group.addChild(block(col(0.26, 0.62, 0.82), [9.0, 0.06, 7.0], at: [3.6, 0.03, 0]))
        // Foamy shoreline.
        group.addChild(block(.white, [0.3, 0.05, 7.0], at: [-0.8, 0.06, 0]))
        // Striped lighthouse (landmark): a tapered stack of red/white bands.
        let bands: [(Float, Float, PlatformColor)] = [
            (1.5, 0.0, col(0.92, 0.92, 0.92)), (1.35, 0.9, col(0.88, 0.26, 0.24)),
            (1.2, 1.8, col(0.92, 0.92, 0.92)), (1.05, 2.7, col(0.88, 0.26, 0.24)),
            (0.9, 3.6, col(0.92, 0.92, 0.92))
        ]
        let lx: Float = -2.6
        for (w, y, c) in bands {
            group.addChild(block(c, [w, 0.95, w], at: [lx, 0.5 + y, -1.6]))
        }
        // Lantern room + light + cap.
        group.addChild(block(col(0.2, 0.22, 0.26), [1.0, 0.3, 1.0], at: [lx, 4.3, -1.6]))
        group.addChild(ball(col(1.0, 0.95, 0.55), 0.45, at: [lx, 4.75, -1.6]))
        group.addChild(block(col(0.7, 0.2, 0.2), [0.9, 0.5, 0.9], at: [lx, 5.2, -1.6]))
        // Palms.
        palmTree(into: group, at: [2.0, 0, -2.2], s: 1.1)
        palmTree(into: group, at: [-3.4, 0, 1.6], s: 0.9)
        // Beach umbrellas.
        for (ux, uc) in [(Float(1.0), col(0.95, 0.35, 0.4)), (Float(2.4), col(0.3, 0.6, 0.9))] {
            group.addChild(block(col(0.9, 0.9, 0.9), [0.08, 1.2, 0.08], at: [ux, 0.6, 1.4]))
            group.addChild(ball(uc, 0.7, at: [ux, 1.25, 1.4], scale: [1, 0.35, 1]))
        }
        // Short pier out over the water.
        for i in 0..<4 {
            group.addChild(block(col(0.55, 0.4, 0.26), [0.8, 0.1, 1.2], at: [1.6 + Float(i) * 0.9, 0.16, -3.4]))
        }
    }

    // MARK: - Clouds (a little sky character)

    private func buildClouds() {
        let spots: [SIMD3<Float>] = [[-6, 9, -8], [9, 10, 4], [3, 11, -12], [14, 9, 12]]
        for s in spots {
            for o in [SIMD3<Float>(0, 0, 0), [0.9, 0.1, 0.2], [-0.9, 0.05, -0.2], [0.3, 0.25, 0.5]] {
                root.addChild(ball(.white, 0.8, at: [s.x + o.x, s.y + o.y, s.z + o.z], scale: [1.3, 0.7, 1.0]))
            }
        }
    }

    // MARK: - Traffic light

    private func buildLight(_ light: Light) {
        let group = Entity()
        group.position = scenePos(light.position.vec, y: 0)

        let pole = ModelLibrary.placeholderBox(
            color: PlatformColor(white: 0.30, alpha: 1), size: [0.16, 2.6, 0.16])
        pole.position = [0, 1.3, 0]
        group.addChild(pole)

        let housing = ModelLibrary.placeholderBox(
            color: PlatformColor(white: 0.15, alpha: 1), size: [0.5, 1.4, 0.4])
        housing.position = [0, 2.7, 0]
        group.addChild(housing)

        let red = ModelLibrary.sphere(radius: 0.16, color: Self.redOff)
        let yellow = ModelLibrary.sphere(radius: 0.16, color: Self.yellowOff)
        let green = ModelLibrary.sphere(radius: 0.16, color: Self.greenOff)
        red.position = [0, 3.1, 0.22]
        yellow.position = [0, 2.7, 0.22]
        green.position = [0, 2.3, 0.22]
        for lamp in [red, yellow, green] { group.addChild(lamp) }

        lamps[light.id] = Lamps(red: red, yellow: yellow, green: green)
        root.addChild(group)
    }

    private func set(_ lamp: ModelEntity, on: Bool, lit: PlatformColor, off: PlatformColor) {
        lamp.model?.materials = [SimpleMaterial(color: on ? lit : off, isMetallic: false)]
    }

    // Lamp colours (lit vs. dimmed).
    private static let redOn = PlatformColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1)
    private static let redOff = PlatformColor(red: 0.35, green: 0.12, blue: 0.12, alpha: 1)
    private static let yellowOn = PlatformColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1)
    private static let yellowOff = PlatformColor(red: 0.38, green: 0.33, blue: 0.12, alpha: 1)
    private static let greenOn = PlatformColor(red: 0.25, green: 0.80, blue: 0.36, alpha: 1)
    private static let greenOff = PlatformColor(red: 0.12, green: 0.30, blue: 0.16, alpha: 1)
}
#endif
