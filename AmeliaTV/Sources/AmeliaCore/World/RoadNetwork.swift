import Foundation

/// One drivable road segment: a straight strip of road between two points with a
/// drivable `width`. The town is a list of these — authored as data (readable on
/// the page), consumed by both rendering and (later) driving/routing.
public struct RoadSegment: Codable, Sendable, Equatable {
    public var a: Vec2
    public var b: Vec2
    public var width: Double

    public init(a: Vec2, b: Vec2, width: Double = 90) {
        self.a = a
        self.b = b
        self.width = width
    }

    /// Closest point on the segment to `p`, and the distance to it.
    public func closest(to p: Vec2) -> (point: Vec2, distance: Double) {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.z * ab.z
        if len2 < 1e-9 { return (a, p.distance(to: a)) }
        var t = ((p - a).x * ab.x + (p - a).z * ab.z) / len2
        t = min(1, max(0, t))
        let proj = a + ab * t
        return (proj, p.distance(to: proj))
    }
}

/// A drivable road network — the GTA-style town's skeleton. Pure data + a little
/// geometry, unit-tested without a GPU. This is the evolution of the old
/// `RouteGraph`: rendered roads become the actual driving surface, and both
/// Adventure routing and Free Drive steering will consume it.
public struct RoadNetwork: Codable, Sendable, Equatable {
    public var segments: [RoadSegment]

    public init(segments: [RoadSegment]) {
        self.segments = segments
    }

    /// Distance from `p` to the nearest road centerline (∞ if there are no roads).
    public func distanceToRoad(_ p: Vec2) -> Double {
        segments.map { $0.closest(to: p).distance }.min() ?? .infinity
    }

    /// True if `p` is within some segment's drivable width — i.e. on the road.
    public func isOnRoad(_ p: Vec2) -> Bool {
        for s in segments where s.closest(to: p).distance <= s.width / 2 {
            return true
        }
        return false
    }
}

public extension RoadNetwork {
    /// The M1 "drivable block": a hand-authored loop with a cross street, so the
    /// bus has corners to take and intersections to cross. Coordinates are real
    /// positions the renderer maps straight to screen.
    static var demoTown: RoadNetwork {
        func seg(_ ax: Double, _ az: Double, _ bx: Double, _ bz: Double) -> RoadSegment {
            RoadSegment(a: Vec2(ax, az), b: Vec2(bx, bz), width: 90)
        }
        return RoadNetwork(segments: [
            // outer loop
            seg(-600, -400, 600, -400),
            seg(600, -400, 600, 400),
            seg(600, 400, -600, 400),
            seg(-600, 400, -600, -400),
            // cross streets
            seg(-600, 0, 600, 0),
            seg(0, -400, 0, 400),
        ])
    }

    /// A clockwise tour of the outer loop — the demo "attract" route the bus
    /// drives when no one is at the controller (so CI captures motion).
    static var demoLoop: [Vec2] {
        [Vec2(-600, -400), Vec2(600, -400), Vec2(600, 400), Vec2(-600, 400)]
    }
}
