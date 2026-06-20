import Foundation

/// A tiny 2D vector used by the Game Core for positions and headings on the
/// ground plane (x, z). The Core works in 2D; the renderer maps it to 3D.
public struct Vec2: Equatable, Codable, Sendable {
    public var x: Double
    public var z: Double

    public init(_ x: Double = 0, _ z: Double = 0) {
        self.x = x
        self.z = z
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.z + b.z) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.z - b.z) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.z * s) }

    public var length: Double { (x * x + z * z).squareRoot() }

    public func distance(to other: Vec2) -> Double { (self - other).length }

    /// Heading in radians where 0 points along +x (matches the prototype's
    /// bus convention in drive/bus.js).
    public var heading: Double { atan2(z, x) }

    public static func fromHeading(_ radians: Double, length: Double = 1) -> Vec2 {
        Vec2(cos(radians) * length, sin(radians) * length)
    }
}
