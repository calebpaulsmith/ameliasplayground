import Foundation

#if canImport(RealityKit)
import RealityKit

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// Resolves a model **id** to a RealityKit `Entity`, loading a USDZ from the app
/// bundle when present and otherwise returning a primitive placeholder. This is
/// the swap-without-code-changes guarantee from docs/tvos/ (F1-06): gameplay
/// never waits on final art, and art can be upgraded later by dropping in a
/// USDZ named after the id.
enum ModelLibrary {

    /// Loads `\(id).usdz` from the bundle, or builds a colored placeholder box.
    static func entity(id: String, placeholderColor: PlatformColor, size: SIMD3<Float>) -> Entity {
        if let url = Bundle.main.url(forResource: id, withExtension: "usdz"),
           let loaded = try? Entity.load(contentsOf: url) {
            return loaded
        }
        return placeholderBox(color: placeholderColor, size: size)
    }

    static func placeholderBox(color: PlatformColor, size: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: size, cornerRadius: size.y * 0.18)
        let material = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// The bus, with two big friendly eyes on its forward (+x) face — the cozy
    /// "friendly vehicle" genre look in original geometry (D-IP-1). Resolves a
    /// `bus.usdz` if present, else a coloured placeholder box.
    static func busEntity(placeholderColor: PlatformColor) -> Entity {
        let bus = entity(id: "bus", placeholderColor: placeholderColor, size: [1.6, 1.1, 0.9])
        for z in [Float(-0.24), 0.24] {
            let white = sphere(radius: 0.17, color: .white)
            white.position = [0.78, 0.18, z]
            bus.addChild(white)
            let pupil = sphere(radius: 0.075, color: PlatformColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1))
            pupil.position = [0.9, 0.18, z]
            bus.addChild(pupil)
        }
        return bus
    }

    static func ground(size: Float, color: PlatformColor) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: size, depth: size)
        let material = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    static func sphere(radius: Float, color: PlatformColor) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// A friendly Rescue-Team vehicle, built from primitives with two big eyes on
    /// its forward (+x) windshield. Distinct silhouette per `role`. Loads
    /// `\(modelRef).usdz` if present, else builds an original placeholder.
    /// All-original designs (D-IP-1).
    static func vehicle(modelRef: String, role: String, color: PlatformColor) -> Entity {
        if let url = Bundle.main.url(forResource: modelRef, withExtension: "usdz"),
           let loaded = try? Entity.load(contentsOf: url) {
            return loaded
        }
        return role == "helicopter" ? builtHelicopter(color: color)
                                    : builtGroundVehicle(role: role, color: color)
    }

    /// Two eyes (white + pupil) on the +x face at the given height/forward x.
    private static func addEyes(to node: Entity, atX x: Float, y: Float,
                               spacing: Float = 0.18, scale: Float = 1) {
        for z in [-spacing, spacing] {
            let white = sphere(radius: 0.13 * scale, color: .white)
            white.position = [x, y, z]
            node.addChild(white)
            let pupil = sphere(radius: 0.055 * scale,
                               color: PlatformColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1))
            pupil.position = [x + 0.1 * scale, y, z]
            node.addChild(pupil)
        }
    }

    private static func wheel() -> ModelEntity {
        let w = sphere(radius: 0.22, color: PlatformColor(white: 0.16, alpha: 1))
        w.scale = [1, 1, 0.5]          // flatten into a disc (axle along z)
        return w
    }

    private static func builtGroundVehicle(role: String, color: PlatformColor) -> Entity {
        let node = Entity()
        let body = placeholderBox(color: color, size: [1.5, 0.7, 0.9])
        body.position = [0, 0.5, 0]
        node.addChild(body)
        let cabin = placeholderBox(color: color, size: [0.7, 0.55, 0.84])
        cabin.position = [0.42, 1.0, 0]
        node.addChild(cabin)
        for x in [Float(-0.5), 0.5] {
            for z in [Float(-0.46), 0.46] {
                let w = wheel()
                w.position = [x, 0.22, z]
                node.addChild(w)
            }
        }
        addEyes(to: node, atX: 0.78, y: 1.02)

        switch role {
        case "fire":
            let ladder = placeholderBox(color: PlatformColor(white: 0.85, alpha: 1),
                                        size: [1.3, 0.08, 0.12])
            ladder.position = [-0.15, 1.05, 0]
            ladder.orientation = simd_quatf(angle: -0.18, axis: [0, 0, 1])
            node.addChild(ladder)
        case "tow":
            let arm = placeholderBox(color: PlatformColor(white: 0.30, alpha: 1),
                                     size: [0.8, 0.1, 0.12])
            arm.position = [-0.7, 1.0, 0]
            arm.orientation = simd_quatf(angle: 0.5, axis: [0, 0, 1])
            node.addChild(arm)
            let hook = placeholderBox(color: PlatformColor(white: 0.22, alpha: 1),
                                      size: [0.12, 0.18, 0.12])
            hook.position = [-1.05, 1.18, 0]
            node.addChild(hook)
        case "ambulance":
            let bar = placeholderBox(color: PlatformColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1),
                                     size: [0.42, 0.12, 0.5])
            bar.position = [0.1, 1.34, 0]
            node.addChild(bar)
            let crossV = placeholderBox(color: PlatformColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),
                                        size: [0.06, 0.34, 0.05])
            crossV.position = [-0.2, 0.55, 0.46]
            node.addChild(crossV)
            let crossH = placeholderBox(color: PlatformColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),
                                        size: [0.34, 0.06, 0.05])
            crossH.position = [-0.2, 0.55, 0.46]
            node.addChild(crossH)
        default:
            break
        }
        return node
    }

    private static func builtHelicopter(color: PlatformColor) -> Entity {
        let node = Entity()
        let cockpit = sphere(radius: 0.5, color: color)
        cockpit.scale = [1.3, 0.95, 0.95]
        cockpit.position = [0.25, 0.85, 0]
        node.addChild(cockpit)
        let boom = placeholderBox(color: color, size: [1.2, 0.14, 0.14])
        boom.position = [-0.75, 0.95, 0]
        node.addChild(boom)
        let fin = placeholderBox(color: color, size: [0.1, 0.4, 0.1])
        fin.position = [-1.3, 1.1, 0]
        node.addChild(fin)
        for z in [Float(-0.32), 0.32] {
            let skid = placeholderBox(color: PlatformColor(white: 0.25, alpha: 1),
                                      size: [1.0, 0.06, 0.06])
            skid.position = [0.2, 0.18, z]
            node.addChild(skid)
        }
        let mast = placeholderBox(color: PlatformColor(white: 0.25, alpha: 1),
                                  size: [0.08, 0.25, 0.08])
        mast.position = [0.25, 1.35, 0]
        node.addChild(mast)
        let rotorA = placeholderBox(color: PlatformColor(white: 0.2, alpha: 1),
                                    size: [1.9, 0.04, 0.14])
        rotorA.position = [0.25, 1.48, 0]
        node.addChild(rotorA)
        let rotorB = placeholderBox(color: PlatformColor(white: 0.2, alpha: 1),
                                    size: [0.14, 0.04, 1.9])
        rotorB.position = [0.25, 1.48, 0]
        node.addChild(rotorB)
        addEyes(to: node, atX: 0.8, y: 0.9)
        return node
    }

    /// A small, friendly NPC figure: a rounded body, a head, and two eyes facing
    /// forward (+z). Original placeholder geometry; swap a USDZ in later by id.
    static func character(color: PlatformColor) -> Entity {
        let node = Entity()
        let body = placeholderBox(color: color, size: [0.5, 0.7, 0.42])
        body.position = [0, 0.35, 0]
        node.addChild(body)
        let head = sphere(radius: 0.26, color: color)
        head.position = [0, 0.92, 0]
        node.addChild(head)
        for x in [Float(-0.1), 0.1] {
            let white = sphere(radius: 0.07, color: .white)
            white.position = [x, 0.96, 0.20]
            node.addChild(white)
            let pupil = sphere(radius: 0.032, color: PlatformColor(white: 0.1, alpha: 1))
            pupil.position = [x, 0.96, 0.25]
            node.addChild(pupil)
        }
        return node
    }

    /// Parses `#rrggbb` (case-insensitive) into a platform color; nil if unparseable.
    static func color(hex: String?) -> PlatformColor? {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return PlatformColor(
            red: CGFloat((v >> 16) & 0xff) / 255.0,
            green: CGFloat((v >> 8) & 0xff) / 255.0,
            blue: CGFloat(v & 0xff) / 255.0,
            alpha: 1
        )
    }
}
#endif
