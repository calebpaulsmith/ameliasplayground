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
        buildRoads(content: content)
        for place in content.places { buildPlace(place) }
        for light in content.lights { buildLight(light) }
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

    // MARK: - Ground & roads

    private func buildGround() {
        let ground = ModelLibrary.ground(size: 200,
            color: PlatformColor(red: 0.50, green: 0.79, blue: 0.46, alpha: 1))
        ground.position = [0, 0, 0]
        root.addChild(ground)
    }

    /// Lays grey road strips along the episode route so the drive reads as a
    /// street through town. The slice route is garage → stop → light → park → home.
    private func buildRoads(content: GameContent) {
        func pos(place id: String) -> Vec2? { content.places.first { $0.id == id }?.position.vec }
        func pos(light id: String) -> Vec2? { content.lights.first { $0.id == id }?.position.vec }

        var pts: [Vec2] = []
        if let g = pos(place: "garage") { pts.append(g) }
        if let s = pos(place: "stopA") { pts.append(s) }
        if let l = pos(light: "light1") { pts.append(l) }
        if let p = pos(place: "park") { pts.append(p) }
        if let g = pos(place: "garage") { pts.append(g) }   // loop home

        for i in 0..<max(0, pts.count - 1) {
            road(from: pts[i], to: pts[i + 1])
        }
    }

    private func road(from a: Vec2, to b: Vec2) {
        let d = b - a
        let len = Float(d.length) * scale
        guard len > 0.01 else { return }
        let width: Float = 1.6
        let strip = ModelLibrary.placeholderBox(
            color: PlatformColor(red: 0.27, green: 0.28, blue: 0.30, alpha: 1),
            size: [len, 0.04, width])
        // Box long axis is local x; align it with the segment direction in XZ.
        let angle = Float(atan2(d.z, d.x))
        let mid = (a + b) * 0.5
        strip.position = scenePos(mid, y: 0.03)
        strip.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
        root.addChild(strip)
    }

    // MARK: - Places

    private func buildPlace(_ place: Place) {
        let tint = ModelLibrary.color(hex: place.beaconColor)
            ?? PlatformColor(white: 0.8, alpha: 1)
        let group = Entity()
        group.position = scenePos(place.position.vec, y: 0)

        switch place.kind {
        case "busStop": buildBusStop(into: group, tint: tint)
        case "park":    buildPark(into: group)
        case "garage":  buildGarage(into: group, tint: tint)
        default:        buildBuilding(into: group, tint: tint)
        }
        root.addChild(group)
    }

    /// A generic friendly storefront: a coloured box with a contrasting roof.
    private func buildBuilding(into group: Entity, tint: PlatformColor) {
        let base = ModelLibrary.placeholderBox(color: tint, size: [2.6, 2.0, 2.6])
        base.position = [0, 1.0, 0]
        group.addChild(base)
        let roof = ModelLibrary.placeholderBox(
            color: PlatformColor(white: 0.95, alpha: 1), size: [2.9, 0.4, 2.9])
        roof.position = [0, 2.1, 0]
        group.addChild(roof)
    }

    /// A bus-stop shelter: a flat roof on two posts with a small sign disc.
    private func buildBusStop(into group: Entity, tint: PlatformColor) {
        let roof = ModelLibrary.placeholderBox(color: tint, size: [2.4, 0.18, 1.2])
        roof.position = [0, 1.7, 0]
        group.addChild(roof)
        for x in [Float(-1.0), 1.0] {
            let post = ModelLibrary.placeholderBox(
                color: PlatformColor(white: 0.85, alpha: 1), size: [0.14, 1.7, 0.14])
            post.position = [x, 0.85, 0.5]
            group.addChild(post)
        }
        let sign = ModelLibrary.sphere(radius: 0.3, color: tint)
        sign.position = [1.2, 2.1, 0.5]
        group.addChild(sign)
    }

    /// A leafy little park: a green mound ringed by a few simple trees.
    private func buildPark(into group: Entity) {
        let lawn = ModelLibrary.sphere(radius: 1.6,
            color: PlatformColor(red: 0.36, green: 0.72, blue: 0.36, alpha: 1))
        lawn.position = [0, 0, 0]       // flattened sphere → a low grassy dome
        lawn.scale = [1, 0.28, 1]
        group.addChild(lawn)
        let offsets: [SIMD2<Float>] = [[-1.2, -0.6], [1.1, 0.4], [0.2, 1.3]]
        for o in offsets {
            let trunk = ModelLibrary.placeholderBox(
                color: PlatformColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1),
                size: [0.22, 0.9, 0.22])
            trunk.position = [o.x, 0.45, o.y]
            group.addChild(trunk)
            let leaves = ModelLibrary.sphere(radius: 0.7,
                color: PlatformColor(red: 0.30, green: 0.66, blue: 0.32, alpha: 1))
            leaves.position = [o.x, 1.3, o.y]
            group.addChild(leaves)
        }
    }

    /// The home garage: a wide warm workshop box with a darker open doorway,
    /// where Mechanic Mom fixes the buses (the full interior + Mom arrive in A2-07).
    private func buildGarage(into group: Entity, tint: PlatformColor) {
        let building = ModelLibrary.placeholderBox(color: tint, size: [3.4, 2.4, 2.8])
        building.position = [0, 1.2, 0]
        group.addChild(building)
        let roof = ModelLibrary.placeholderBox(
            color: PlatformColor(red: 0.86, green: 0.36, blue: 0.30, alpha: 1),
            size: [3.7, 0.4, 3.1])
        roof.position = [0, 2.5, 0]
        group.addChild(roof)
        let door = ModelLibrary.placeholderBox(
            color: PlatformColor(white: 0.18, alpha: 1), size: [1.8, 1.6, 0.1])
        door.position = [0, 0.8, 1.41]
        group.addChild(door)
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
