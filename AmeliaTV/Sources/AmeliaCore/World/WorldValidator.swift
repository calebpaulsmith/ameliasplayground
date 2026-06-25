import Foundation

/// A single problem found in a `WorldLayout`. Carries a machine-checkable `kind`
/// (for tests) and a human-readable `message` (for CI logs / PR reports).
public struct WorldValidationIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Two building footprints overlap each other.
        case buildingOverlapsBuilding(String, String)
        /// A building footprint sits on top of a drivable road strip — i.e. there's
        /// a road running under the building.
        case buildingOverlapsRoad(building: String, roadIndex: Int)
        /// A story-relevant place is not on any road, so the bus can't reach it.
        case placeOffRoad(String)
    }

    public var kind: Kind
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// Validates a `WorldLayout`'s geometry on CI without a GPU — the "world you can
/// actually author and see" needs a check that a building isn't dropped on a road
/// and a bus stop isn't stranded off it. Pure data + geometry, fully unit-tested.
public enum WorldValidator {

    /// Validate `layout`, returning every issue found (empty == clean).
    ///
    /// - `buildingPadding`: minimum clear gap required between buildings.
    /// - `roadPadding`: extra clearance required between a building and a road
    ///   strip (on top of the road's half-width).
    public static func validate(_ layout: WorldLayout,
                                buildingPadding: Double = 0,
                                roadPadding: Double = 0) -> [WorldValidationIssue] {
        var issues: [WorldValidationIssue] = []

        // --- building vs building ---
        let b = layout.buildings
        if b.count > 1 {
            for i in 0..<(b.count - 1) {
                for j in (i + 1)..<b.count where b[i].overlaps(b[j], padding: buildingPadding) {
                    issues.append(.init(
                        kind: .buildingOverlapsBuilding(b[i].id, b[j].id),
                        message: "Buildings '\(b[i].id)' and '\(b[j].id)' overlap."))
                }
            }
        }

        // --- building vs road ---
        // Grow the building's box by the road's half-width (a conservative
        // box-Minkowski stand-in for the road's capsule) and test the road
        // centerline against it: if the line clips the grown box, the road's
        // drivable strip reaches under the building.
        for bf in b {
            for (idx, seg) in layout.roads.segments.enumerated() {
                let grow = seg.width / 2 + roadPadding
                if segmentIntersectsBox(a: seg.a, b: seg.b,
                                        minX: bf.minX - grow, maxX: bf.maxX + grow,
                                        minZ: bf.minZ - grow, maxZ: bf.maxZ + grow) {
                    issues.append(.init(
                        kind: .buildingOverlapsRoad(building: bf.id, roadIndex: idx),
                        message: "Building '\(bf.id)' overlaps road segment #\(idx) "
                            + "(\(fmt(seg.a))→\(fmt(seg.b)), width \(Int(seg.width)))."))
                }
            }
        }

        // --- places on road --- (sorted so output is deterministic)
        for (id, pos) in layout.places.places.sorted(by: { $0.key < $1.key })
        where !layout.roads.isOnRoad(pos) {
            issues.append(.init(
                kind: .placeOffRoad(id),
                message: "Place '\(id)' at \(fmt(pos)) is not on any road."))
        }

        return issues
    }

    /// Liang–Barsky clip: does the segment `a`→`b` intersect the axis-aligned box
    /// `[minX,maxX] × [minZ,maxZ]`? Handles segments that start/end inside the box.
    static func segmentIntersectsBox(a: Vec2, b: Vec2,
                                     minX: Double, maxX: Double,
                                     minZ: Double, maxZ: Double) -> Bool {
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dz = b.z - a.z
        let clips: [(p: Double, q: Double)] = [
            (-dx, a.x - minX), (dx, maxX - a.x),   // x slabs
            (-dz, a.z - minZ), (dz, maxZ - a.z),   // z slabs
        ]
        for c in clips {
            if c.p == 0 {
                // Parallel to this slab: outside it means no intersection.
                if c.q < 0 { return false }
            } else {
                let r = c.q / c.p
                if c.p < 0 {
                    if r > t1 { return false }
                    if r > t0 { t0 = r }
                } else {
                    if r < t0 { return false }
                    if r < t1 { t1 = r }
                }
            }
        }
        return t0 <= t1
    }

    private static func fmt(_ v: Vec2) -> String {
        "(\(Int(v.x.rounded())), \(Int(v.z.rounded())))"
    }
}

public extension Array where Element == WorldValidationIssue {
    var buildingBuildingOverlaps: [WorldValidationIssue] {
        filter { if case .buildingOverlapsBuilding = $0.kind { return true } else { return false } }
    }
    var buildingRoadOverlaps: [WorldValidationIssue] {
        filter { if case .buildingOverlapsRoad = $0.kind { return true } else { return false } }
    }
    var placesOffRoad: [WorldValidationIssue] {
        filter { if case .placeOffRoad = $0.kind { return true } else { return false } }
    }
}
