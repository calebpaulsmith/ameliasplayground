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
