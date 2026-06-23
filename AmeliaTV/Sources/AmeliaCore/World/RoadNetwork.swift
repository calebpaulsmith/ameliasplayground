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

    /// The junction points where road segments meet — every position shared by the
    /// endpoints of two or more distinct segments. The renderer paints an asphalt
    /// pad here so crossings read as real intersections. Order is deterministic.
    public func intersections(tolerance: Double = 1.0) -> [Vec2] {
        var endpoints: [Vec2] = []
        for s in segments { endpoints.append(s.a); endpoints.append(s.b) }
        var result: [Vec2] = []
        for (i, p) in endpoints.enumerated() {
            // count other endpoints that coincide with p
            let shared = endpoints.enumerated().contains { (j, q) in
                j != i && q.distance(to: p) <= tolerance
            }
            guard shared else { continue }
            if !result.contains(where: { $0.distance(to: p) <= tolerance }) {
                result.append(p)
            }
        }
        return result
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

    /// The Welles Park neighborhood (Lincoln Square): a big park bounded by
    /// **Western Ave** (straight, west), **Montrose Ave** (north), the **Lincoln
    /// Ave** diagonal (north-east → south-west, east), and **Sunnyside Ave**
    /// (south). The park sits inside; church/library/apartments sit outside.
    static var welles: RoadNetwork {
        func seg(_ ax: Double, _ az: Double, _ bx: Double, _ bz: Double) -> RoadSegment {
            RoadSegment(a: Vec2(ax, az), b: Vec2(bx, bz), width: 110)
        }
        return RoadNetwork(segments: [
            seg(-800, -700, -800, 700),   // Western (west, N–S)
            seg(-800, -700, 550, -700),   // Montrose (north)
            seg(550, -700, 820, 700),     // Lincoln (diagonal NE→SW, east)
            seg(-800, 700, 820, 700),     // Sunnyside (south)
            // The avenues keep going past each corner — short stubs out of every
            // junction so the park reads as one block in a bigger grid (each corner
            // becomes a four-way stop). The bus still tours the perimeter loop.
            seg(-800, -700, -800, -980),  // Western continues north (NW)
            seg(-800, -700, -1080, -700), // Montrose continues west (NW)
            seg(550, -700, 550, -980),    // cross street north (NE)
            seg(550, -700, 830, -700),    // Montrose continues east (NE)
            seg(820, 700, 820, 980),      // cross street south (SE)
            seg(820, 700, 1100, 700),     // Sunnyside continues east (SE)
            seg(-800, 700, -800, 980),    // Western continues south (SW)
            seg(-800, 700, -1080, 700),   // Sunnyside continues west (SW)
        ])
    }

    /// Clockwise tour of the Welles perimeter (NW → NE → SE → SW), including the
    /// Lincoln diagonal — the demo attract route on the new map.
    static var wellesLoop: [Vec2] {
        [Vec2(-800, -700), Vec2(550, -700), Vec2(820, 700), Vec2(-800, 700)]
    }
}
