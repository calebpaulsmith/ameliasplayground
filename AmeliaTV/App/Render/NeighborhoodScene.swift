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

    /// Last state shown per light, so we only rebuild lamp materials when a light
    /// actually changes — not 60 times a second (perf: avoids per-frame allocations).
    private var litStates: [String: TrafficLight.State] = [:]

    // Animatable landmarks/props, captured at build time so the world can come
    // alive each frame (CL-03 — "the world reacts", GAME_DESIGN.md §4a).
    private var flag: ModelEntity?              // school flag — flutters
    private var lighthouseBeam: Entity?         // sweeps around the seaside
    private var busStopSign: ModelEntity?       // idly spins
    private var fountainSpray: ModelEntity?     // bobs up and down
    private var clouds: [Entity] = []           // drift across the sky
    private var birds: [Bird] = []              // perch, then scatter on a honk

    // Cozy-mood elements that respond to the time of day (CL-05): window panes and
    // lamp globes glow warm as night falls, and stars fade in overhead.
    private var windowPanes: [ModelEntity] = []
    private var lampGlobes: [ModelEntity] = []
    private var stars: [ModelEntity] = []
    private var lastNight: Float = -1           // throttles night material rebuilds

    /// Maps Game Core ground units to scene meters (matches the engine's bus).
    private let scale: Float

    /// District centres (world units), so the street-lining houses can skip the
    /// blocks where a landmark already sits.
    private var placeCenters: [Vec2] = []

    init(content: GameContent, scale: Float) {
        self.scale = scale
        placeCenters = content.places.map { $0.position.vec }
        buildGround()
        let segments = routeLoop(content: content)
        buildRoads(segments)
        buildScenery(along: segments)
        for place in content.places { buildPlace(place) }
        for light in content.lights { buildLight(light) }
        buildVehicles(content)
        buildBirds(content)
        buildClouds()
        buildStars()
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

    /// Lights the lamp matching each light's state and dims the others. Takes the
    /// raw snapshot and diffs against the last shown state, so a steady light costs
    /// nothing per frame (only a changed light rebuilds its three lamp materials).
    func updateLights(_ snapshot: [TrafficLight]) {
        for light in snapshot {
            guard litStates[light.id] != light.state else { continue }
            litStates[light.id] = light.state
            guard let l = lamps[light.id] else { continue }
            set(l.red, on: light.state == .red, lit: Self.redOn, off: Self.redOff)
            set(l.yellow, on: light.state == .yellow, lit: Self.yellowOn, off: Self.yellowOff)
            set(l.green, on: light.state == .green, lit: Self.greenOn, off: Self.greenOff)
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

    /// Lines every street with lamp posts, a ribbon of trees, and rows of cute
    /// houses set back on both kerbs — so the world reads as a real neighborhood you
    /// drive *through*, not a few props by the road. Deterministic placement; houses
    /// skip blocks where a district landmark already sits.
    private func buildScenery(along segments: [(Vec2, Vec2)]) {
        let bodies = [col(0.96, 0.86, 0.62), col(0.90, 0.62, 0.55), col(0.62, 0.80, 0.93),
                      col(0.80, 0.86, 0.62), col(0.92, 0.80, 0.86), col(0.70, 0.84, 0.80)]
        let roofs  = [col(0.82, 0.40, 0.34), col(0.42, 0.46, 0.62), col(0.56, 0.40, 0.30),
                      col(0.72, 0.52, 0.30), col(0.40, 0.55, 0.45)]
        for (idx, seg) in segments.enumerated() {
            let (a, b) = seg
            let d = b - a
            let len = d.length
            guard len > 6 else { continue }
            let inv = 1.0 / len
            let perp = Vec2(-d.z * inv, d.x * inv)          // unit perpendicular
            let n = max(1, Int(len / 30))
            for k in 1...n {
                let t = Double(k) / Double(n + 1)
                let on = a + d * t
                let lampSide: Double = (k % 2 == 0) ? 1 : -1
                // A lamp at one kerb, a tree at the other (offsets are world units → ×0.12 m).
                lampPost(at: scenePos(on + perp * (12 * lampSide), y: 0))
                let treeAt = scenePos(on + perp * (24 * -lampSide), y: 0)
                switch (idx + k) % 3 {
                case 0: roundTree(at: treeAt, leaf: col(0.30, 0.66, 0.32))
                case 1: roundTree(at: treeAt, leaf: col(0.40, 0.70, 0.30), s: 1.2)
                default: pineTree(at: treeAt)
                }
                // A house set back on each side — a proper lined street. Every other
                // stop, so the row reads full without flooding the phone with entities.
                if k % 2 == 1 {
                    for side in [Double(-1), 1] {
                        let hp = on + perp * (46 * side)
                        guard !nearPlace(hp, within: 40) else { continue }
                        let toRoad = perp * (-side)
                        house(at: scenePos(hp, y: 0),
                              faceDir: SIMD2(Float(toRoad.x), Float(toRoad.z)),
                              body: bodies[(idx * 5 + k + (side > 0 ? 1 : 0)) % bodies.count],
                              roof: roofs[(idx * 3 + k) % roofs.count])
                    }
                }
            }
        }
    }

    /// True if a district landmark sits within `r` world units of `v`.
    private func nearPlace(_ v: Vec2, within r: Double) -> Bool {
        for c in placeCenters where (c - v).length < r { return true }
        return false
    }

    /// One cosy house, front (door + windows) on local +x, turned so that face
    /// looks at the road. Original placeholder geometry; windows glow at night.
    private func house(at p: SIMD3<Float>, faceDir: SIMD2<Float>,
                       body: PlatformColor, roof: PlatformColor) {
        let g = Entity()
        g.position = p
        g.orientation = simd_quatf(angle: -atan2(faceDir.y, faceDir.x), axis: [0, 1, 0])

        g.addChild(block(body, [2.6, 2.2, 3.2], at: [0, 1.1, 0]))          // walls
        g.addChild(block(roof, [3.0, 0.45, 3.6], at: [0, 2.45, 0]))        // eaves
        g.addChild(block(roof, [1.5, 0.6, 3.6], at: [0, 2.8, 0]))          // ridge
        g.addChild(block(col(0.45, 0.30, 0.20), [0.12, 1.2, 0.8], at: [1.31, 0.6, 0]))  // door
        for z in [Float(-1.0), 1.0] {                                       // two front windows
            let pane = block(col(0.80, 0.92, 1.0), [0.1, 0.6, 0.7], at: [1.31, 1.45, z])
            g.addChild(pane)
            windowPanes.append(pane)
        }
        g.addChild(block(col(0.6, 0.42, 0.34), [0.32, 0.7, 0.32], at: [-0.5, 2.85, 0.9]))  // chimney
        g.addChild(block(col(0.42, 0.72, 0.40), [1.6, 0.06, 3.2], at: [2.1, 0.04, 0]))     // front lawn
        g.addChild(block(col(0.86, 0.84, 0.70), [1.6, 0.07, 0.5], at: [2.1, 0.05, 0]))     // path
        root.addChild(g)
    }

    // MARK: - Reusable set pieces

    private func lampPost(at p: SIMD3<Float>) {
        root.addChild(block(col(0.25, 0.26, 0.28), [0.12, 2.2, 0.12], at: [p.x, 1.1, p.z]))
        root.addChild(block(col(0.25, 0.26, 0.28), [0.5, 0.1, 0.12], at: [p.x + 0.2, 2.1, p.z]))
        let globe = ball(col(1.0, 0.93, 0.6), 0.16, at: [p.x + 0.4, 2.05, p.z])
        root.addChild(globe)
        lampGlobes.append(globe)
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
            let pane = block(col(0.75, 0.90, 1.0), [0.45, 0.55, 0.06],
                             at: [start + Float(i) * spacing, y, faceZ])
            g.addChild(pane)
            windowPanes.append(pane)
        }
    }

    // MARK: - Places (each its own district + landmark)

    private func buildPlace(_ place: Place) {
        let tint = ModelLibrary.color(hex: place.beaconColor)
            ?? PlatformColor(white: 0.8, alpha: 1)
        let group = Entity()
        group.position = scenePos(place.position.vec, y: 0)

        // Real art wins: a `place_<id>.usdz` replaces the whole primitive district
        // (it carries its own landmark/dressing). The animated props the engine
        // looks for stay nil, so `updateAmbient` safely skips them.
        if let model = ModelLibrary.loadUSDZ("place_\(place.id)") {
            group.addChild(model)
            root.addChild(group)
            return
        }

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
        sign.addChild(block(.white, [0.34, 0.34, 0.04], at: [0, 0, 0.36]))  // face, spins with it
        group.addChild(sign)
        self.busStopSign = sign
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
        let spray = ball(col(0.55, 0.8, 0.95), 0.34, at: [fx, 1.0, fz], scale: [1, 1.3, 1])
        group.addChild(spray)
        self.fountainSpray = spray
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
        // Flag pole flying a flag (the flag flutters — captured for animation).
        group.addChild(block(col(0.9, 0.9, 0.92), [0.1, 3.2, 0.1], at: [-1.8, 1.6, 0.8]))
        let flag = block(col(0.2, 0.55, 0.85), [0.9, 0.6, 0.04], at: [-1.35, 3.0, 0.8])
        group.addChild(flag)
        self.flag = flag
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
        // A pale beam that sweeps around from the lantern (pivot rotated each frame).
        let beamPivot = Entity()
        beamPivot.position = [lx, 4.75, -1.6]
        let beam = block(col(1.0, 0.96, 0.7), [6.0, 0.22, 0.5], at: [3.0, 0, 0])
        beamPivot.addChild(beam)
        group.addChild(beamPivot)
        self.lighthouseBeam = beamPivot
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
            let cloud = Entity()
            cloud.position = s
            for o in [SIMD3<Float>(0, 0, 0), [0.9, 0.1, 0.2], [-0.9, 0.05, -0.2], [0.3, 0.25, 0.5]] {
                cloud.addChild(ball(.white, 0.8, at: o, scale: [1.3, 0.7, 1.0]))
            }
            root.addChild(cloud)
            clouds.append(cloud)
        }
    }

    // MARK: - Cozy mood (time of day: window glow, lamp glow, stars)

    /// Scatters little unlit stars high overhead, hidden by day (scale 0) and faded
    /// in at night by `setNight`. Unlit so they shine regardless of the sun.
    private func buildStars() {
        for _ in 0..<44 {
            let star = ball(.white, 0.16, at: [Float.random(in: -42...42),
                                               Float.random(in: 13...20),
                                               Float.random(in: -42...42)])
            star.model?.materials = [UnlitMaterial(color: .white)]
            star.scale = .zero
            star.isEnabled = false
            root.addChild(star)
            stars.append(star)
        }
    }

    /// Drives the time-of-day wash, `f` in 0 (bright day) … 1 (gentle night). Windows
    /// and lamp globes glow warm (unlit, so they "light up"), and the stars fade in.
    /// Throttled so materials only rebuild when the light meaningfully changes.
    func setNight(_ f: Float) {
        let n = max(0, min(1, f))
        guard abs(n - lastNight) >= 0.015 else { return }
        lastNight = n

        // Windows: cool glass by day → warm glow by night (unlit, so they "light up").
        let day = SIMD3<Float>(0.75, 0.90, 1.0), warm = SIMD3<Float>(1.0, 0.86, 0.5)
        let glass = UnlitMaterial(color: rgb(day + (warm - day) * n))
        for pane in windowPanes { pane.model?.materials = [glass] }

        // Lamp globes brighten into the dusk.
        let l = 0.55 + 0.45 * n
        let lamp = UnlitMaterial(color: rgb([l, l * 0.92, l * 0.6]))
        for globe in lampGlobes { globe.model?.materials = [lamp] }

        // Stars fade/scale in once it's properly dim.
        let s = max(0, (n - 0.15) / 0.85)
        for star in stars {
            star.isEnabled = s > 0.02
            let sz = 0.12 + 0.14 * s
            star.scale = [sz, sz, sz]
        }
    }

    private func rgb(_ c: SIMD3<Float>) -> PlatformColor {
        PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    // MARK: - Birds (perch near the stops; scatter when Amelia honks)

    /// A small bird: a body, head, beak, and two wing pivots that flap. Original
    /// placeholder geometry. Perches on the ground and springs back home after a
    /// honk sends it fluttering up.
    private final class Bird {
        let node = Entity()
        let leftWing = Entity()
        let rightWing = Entity()
        let perch: SIMD3<Float>
        var pos: SIMD3<Float>
        var vel: SIMD3<Float> = .zero
        let phase: Float
        init(perch: SIMD3<Float>) {
            self.perch = perch
            self.pos = perch
            self.phase = Float.random(in: 0 ... (2 * Float.pi))
        }
    }

    private func makeBird(at p: SIMD3<Float>, color: PlatformColor) -> Bird {
        let bird = Bird(perch: p)
        bird.node.position = p
        bird.node.addChild(ball(color, 0.13, at: [0, 0, 0], scale: [1.3, 1.0, 1.0]))    // body
        bird.node.addChild(ball(color, 0.08, at: [0.15, 0.06, 0]))                       // head
        bird.node.addChild(block(col(0.95, 0.7, 0.2), [0.09, 0.03, 0.03], at: [0.24, 0.06, 0]))  // beak
        for side in [Float(-1), 1] {
            let pivot = side < 0 ? bird.leftWing : bird.rightWing
            pivot.position = [0, 0.02, side * 0.05]
            pivot.addChild(block(color, [0.20, 0.03, 0.16], at: [0, 0, side * 0.10]))
            bird.node.addChild(pivot)
        }
        return bird
    }

    /// Perches a few small flocks near the places the bus dwells by, so a child who
    /// honks gets the delight of seeing them scatter and resettle.
    private func buildBirds(_ content: GameContent) {
        let flocks = ["stopA", "park", "beach"]
        let colors = [col(0.32, 0.34, 0.40), col(0.55, 0.40, 0.30), col(0.22, 0.22, 0.26)]
        for (fi, pid) in flocks.enumerated() {
            guard let place = content.places.first(where: { $0.id == pid }) else { continue }
            let base = scenePos(place.position.vec, y: 0.15)
            for j in 0..<3 {
                let off = SIMD3<Float>(Float(j) * 0.55 - 0.55, 0, -2.4 - Float(j) * 0.35)
                let bird = makeBird(at: [base.x + off.x, base.y, base.z + off.z],
                                    color: colors[fi % colors.count])
                root.addChild(bird.node)
                birds.append(bird)
            }
        }
    }

    // MARK: - Ambient life (called every frame by the engine)

    private func length(_ v: SIMD3<Float>) -> Float { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }

    /// Animates the world's continuous life: the flag flutters, the lighthouse beam
    /// sweeps, the bus-stop sign and fountain play, clouds drift, and birds settle.
    func updateAmbient(elapsed: Double, dt: Double) {
        let t = Float(elapsed)
        flag?.orientation = simd_quatf(angle: 0.20 * sin(t * 3.5), axis: [0, 1, 0])
            * simd_quatf(angle: 0.07 * sin(t * 5.0 + 1), axis: [1, 0, 0])
        lighthouseBeam?.orientation = simd_quatf(angle: t * 0.8, axis: [0, 1, 0])
        busStopSign?.orientation = simd_quatf(angle: t * 0.6, axis: [0, 1, 0])
        if let spray = fountainSpray {
            spray.position.y = 1.0 + 0.12 * sin(t * 4.0)
            spray.scale = [1, 1.3 + 0.18 * sin(t * 4.0), 1]
        }
        for (i, cloud) in clouds.enumerated() {
            cloud.position.x += Float(dt) * 0.22
            if cloud.position.x > 22 { cloud.position.x = -22 + Float(i) * 0.01 }
        }
        for b in birds { updateBird(b, dt: Float(dt), t: t) }
    }

    private func updateBird(_ b: Bird, dt: Float, t: Float) {
        // Spring the bird home to its perch with drag, so a scatter resettles.
        let toHome = b.perch - b.pos
        b.vel += toHome * 6.0 * dt
        b.vel -= b.vel * 2.2 * dt
        b.pos += b.vel * dt
        if b.pos.y < b.perch.y { b.pos.y = b.perch.y; if b.vel.y < 0 { b.vel.y = 0 } }
        b.node.position = b.pos

        let speed = length(b.vel)
        if speed > 0.3 {
            b.node.orientation = simd_quatf(angle: atan2(-b.vel.z, b.vel.x), axis: [0, 1, 0])
        }
        // Wings always shuffle a little; flap fast while in the air.
        let flap = (0.18 + min(1, speed * 1.5)) * sin(t * (11 + speed * 6) + b.phase)
        b.leftWing.orientation = simd_quatf(angle: flap, axis: [1, 0, 0])
        b.rightWing.orientation = simd_quatf(angle: -flap, axis: [1, 0, 0])
    }

    /// Amelia honked: nearby birds startle upward and scatter (they spring back).
    func honk(busPos: SIMD3<Float>) {
        for b in birds {
            var dir = b.perch - busPos
            dir.y = 0
            let d = length(dir)
            guard d < 8 else { continue }
            let horiz = d > 0.001 ? dir / d : SIMD3<Float>(Float.random(in: -1...1), 0, Float.random(in: -1...1))
            b.vel += horiz * Float.random(in: 2.0...4.0)
            b.vel.y += Float.random(in: 4.0...6.5)
            b.vel.x += Float.random(in: -1.2...1.2)
            b.vel.z += Float.random(in: -1.2...1.2)
        }
    }

    // MARK: - Traffic light

    private func buildLight(_ light: Light) {
        let group = Entity()
        group.position = scenePos(light.position.vec, y: 0)

        // A zebra crosswalk painted across the road where the bus stops (road
        // centre); the light itself stands on the kerb just beyond it.
        for i in -2...2 {
            group.addChild(block(.white, [0.2, 0.05, 2.2], at: [Float(i) * 0.45, 0.05, 0]))
        }
        let curbZ: Float = -1.7

        let pole = ModelLibrary.placeholderBox(
            color: PlatformColor(white: 0.30, alpha: 1), size: [0.16, 2.6, 0.16])
        pole.position = [0, 1.3, curbZ]
        group.addChild(pole)

        let housing = ModelLibrary.placeholderBox(
            color: PlatformColor(white: 0.15, alpha: 1), size: [0.5, 1.4, 0.4])
        housing.position = [0, 2.7, curbZ]
        group.addChild(housing)

        let red = ModelLibrary.sphere(radius: 0.16, color: Self.redOff)
        let yellow = ModelLibrary.sphere(radius: 0.16, color: Self.yellowOff)
        let green = ModelLibrary.sphere(radius: 0.16, color: Self.greenOff)
        red.position = [0, 3.1, curbZ + 0.22]
        yellow.position = [0, 2.7, curbZ + 0.22]
        green.position = [0, 2.3, curbZ + 0.22]
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
