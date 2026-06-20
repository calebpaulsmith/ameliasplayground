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
