import Foundation

/// The kind of a building footprint — drives the renderer's per-building charm
/// (awnings, signs, doors) and reads on the page as what each block *is*. Pure
/// data: no rendering or art dependency.
public enum BuildingKind: String, Codable, Sendable, CaseIterable {
    case apartments, restaurant, shop, school, salon, barber, church, library
}

/// A building's top-down footprint in world coordinates — the *logic* underneath
/// the renderer's faked-height (¾) look. Authored as data so the layout is
/// readable on the page and validatable on CI without a GPU (the 2D pivot's whole
/// point: "a world you can actually author and see").
///
/// `width` is the x-extent and `depth` the z-extent (full, not half), matching the
/// renderer's `CGSize(width:height:)` where `height` maps to the z (depth) axis.
public struct BuildingFootprint: Codable, Sendable, Equatable {
    public var id: String
    public var center: Vec2
    public var width: Double
    public var depth: Double
    /// Faked render height (¾ look) — informational; not used by validation.
    public var height: Double
    public var kind: BuildingKind

    public init(id: String, center: Vec2, width: Double, depth: Double,
                height: Double = 100, kind: BuildingKind) {
        self.id = id
        self.center = center
        self.width = width
        self.depth = depth
        self.height = height
        self.kind = kind
    }

    public var halfWidth: Double { width / 2 }
    public var halfDepth: Double { depth / 2 }
    public var minX: Double { center.x - halfWidth }
    public var maxX: Double { center.x + halfWidth }
    public var minZ: Double { center.z - halfDepth }
    public var maxZ: Double { center.z + halfDepth }

    /// True if this footprint's axis-aligned box overlaps `other`'s, with both
    /// boxes grown by `padding` (so a positive padding flags near-touches).
    public func overlaps(_ other: BuildingFootprint, padding: Double = 0) -> Bool {
        abs(center.x - other.center.x) < halfWidth + other.halfWidth + padding &&
        abs(center.z - other.center.z) < halfDepth + other.halfDepth + padding
    }
}

/// The authoritative town layout — the single source of truth for *where things
/// are*: the drivable `RoadNetwork`, the authored building footprints, and the
/// story-relevant `places`. Both the renderer and the Adventure logic should read
/// from this so they can never drift, and `WorldValidator` can gate it on CI.
public struct WorldLayout: Sendable, Equatable {
    public var roads: RoadNetwork
    public var buildings: [BuildingFootprint]
    public var places: TownMap

    public init(roads: RoadNetwork, buildings: [BuildingFootprint], places: TownMap) {
        self.roads = roads
        self.buildings = buildings
        self.places = places
    }

    /// The authored footprint with this id, if any. The renderer looks landmarks
    /// up by id so it reads position/size from this single source of truth rather
    /// than hardcoding them.
    public func building(id: String) -> BuildingFootprint? {
        buildings.first { $0.id == id }
    }
}

public extension WorldLayout {
    /// The Welles Park neighborhood as authored data. The footprints here mirror
    /// the hand-placed landmark/charm-anchor buildings the renderer draws today
    /// (`TownScene.buildings` + the church/library/corner-restaurant builders) — the
    /// first step of migrating the town layout out of the renderer and into Core
    /// (PLAN_2D Part 1, "data-driven world"). The procedural streetwall fill is not
    /// captured yet.
    ///
    /// Setback used by the renderer for the corner restaurant:
    /// `55 + parkway(46) + sidewalk(40) = 141`.
    static var welles: WorldLayout {
        let setback = 55.0 + 46.0 + 40.0          // = 141 (matches TownScene.buildingSetback)
        let cornerRestaurantZ = -700.0 - setback - 75.0   // = -916

        let buildings: [BuildingFootprint] = [
            // West of Western Ave: apartments along the frontage.
            .init(id: "apt-western-n", center: Vec2(-1040, -360), width: 220, depth: 300, height: 150, kind: .apartments),
            .init(id: "apt-western-s", center: Vec2(-1040, 60),  width: 220, depth: 260, height: 120, kind: .apartments),
            // South of Sunnyside: the school (sits in the block, clear of the middle
            // avenue at x=-130) + a restaurant.
            .init(id: "school",        center: Vec2(-400, 975),  width: 280, depth: 220, height: 100, kind: .school),
            .init(id: "restaurant-sunnyside", center: Vec2(220, 960), width: 200, depth: 180, height: 90, kind: .restaurant),
            // North of Montrose: a barber + a salon (barber clear of Western at x=-800).
            .init(id: "barber",        center: Vec2(-660, -940), width: 150, depth: 150, height: 80, kind: .barber),
            .init(id: "salon",         center: Vec2(-500, -940), width: 150, depth: 150, height: 80, kind: .salon),
            // North frontage: the church (its own renderer builder; footprint reserved),
            // nudged clear of the middle avenue at x=-130.
            .init(id: "church",        center: Vec2(-300, -945), width: 220, depth: 170, height: 90, kind: .church),
            // East across Lincoln Ave: the library (the re-projecting perspective landmark).
            .init(id: "library",       center: Vec2(1020, 300),  width: 230, depth: 200, height: 110, kind: .library),
            // Restaurant on the north frontage near the corner, in the block west of
            // the NE cross street at x=550, with café seating.
            .init(id: "restaurant-corner", center: Vec2(390, cornerRestaurantZ), width: 200, depth: 150, height: 85, kind: .restaurant),
        ]
        return WorldLayout(roads: .welles, buildings: buildings, places: .demo)
    }
}
