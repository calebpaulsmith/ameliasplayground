import XCTest
@testable import AmeliaCore

/// Phase 1 of the data-driven world: the layout now lives in Core as
/// `WorldLayout`, and `WorldValidator` gates it on CI without a GPU. These tests
/// prove the detector works and lock the invariants that must always hold
/// (buildings don't overlap each other; every story place is reachable on a road),
/// and surface — without failing the build — the pre-existing "road under a
/// building" overlaps in the authored map for a human to clear when authoring.
final class WorldValidatorTests: XCTestCase {

    // MARK: Geometry helper

    func testSegmentThroughBoxIntersects() {
        XCTAssertTrue(WorldValidator.segmentIntersectsBox(
            a: Vec2(-10, 0), b: Vec2(10, 0), minX: -5, maxX: 5, minZ: -5, maxZ: 5))
    }

    func testSegmentBesideBoxDoesNotIntersect() {
        XCTAssertFalse(WorldValidator.segmentIntersectsBox(
            a: Vec2(-10, 100), b: Vec2(10, 100), minX: -5, maxX: 5, minZ: -5, maxZ: 5))
    }

    func testSegmentEndingInsideBoxIntersects() {
        // Starts well outside, ends inside the box.
        XCTAssertTrue(WorldValidator.segmentIntersectsBox(
            a: Vec2(-100, 0), b: Vec2(0, 0), minX: -5, maxX: 5, minZ: -5, maxZ: 5))
    }

    func testParallelSegmentOutsideSlabDoesNotIntersect() {
        // Horizontal segment far above the box: parallel to x slabs, outside z.
        XCTAssertFalse(WorldValidator.segmentIntersectsBox(
            a: Vec2(-100, 50), b: Vec2(100, 50), minX: -5, maxX: 5, minZ: -5, maxZ: 5))
    }

    // MARK: Detector correctness (synthetic, certain)

    func testDetectsBuildingOnRoad() {
        let layout = WorldLayout(
            roads: RoadNetwork(segments: [RoadSegment(a: Vec2(-100, 0), b: Vec2(100, 0), width: 80)]),
            buildings: [BuildingFootprint(id: "onRoad", center: Vec2(0, 0), width: 60, depth: 60, kind: .shop)],
            places: TownMap(places: [:]))
        XCTAssertEqual(WorldValidator.validate(layout).buildingRoadOverlaps.count, 1)
    }

    func testDetectsBuildingClearOfRoad() {
        let layout = WorldLayout(
            roads: RoadNetwork(segments: [RoadSegment(a: Vec2(-100, 0), b: Vec2(100, 0), width: 80)]),
            // Far below the 80-wide road (strip ends at z=40); building starts at z=170.
            buildings: [BuildingFootprint(id: "clear", center: Vec2(0, 200), width: 60, depth: 60, kind: .shop)],
            places: TownMap(places: [:]))
        XCTAssertTrue(WorldValidator.validate(layout).buildingRoadOverlaps.isEmpty)
    }

    func testDetectsOverlappingBuildings() {
        let layout = WorldLayout(
            roads: RoadNetwork(segments: []),
            buildings: [
                BuildingFootprint(id: "a", center: Vec2(0, 0), width: 100, depth: 100, kind: .shop),
                BuildingFootprint(id: "b", center: Vec2(50, 0), width: 100, depth: 100, kind: .shop),
            ],
            places: TownMap(places: [:]))
        XCTAssertEqual(WorldValidator.validate(layout).buildingBuildingOverlaps.count, 1)
    }

    func testDetectsPlaceOffRoad() {
        let layout = WorldLayout(
            roads: RoadNetwork(segments: [RoadSegment(a: Vec2(-100, 0), b: Vec2(100, 0), width: 80)]),
            buildings: [],
            places: TownMap(places: ["stranded": Vec2(0, 500)]))
        XCTAssertEqual(WorldValidator.validate(layout).placesOffRoad.count, 1)
    }

    // MARK: The authored Welles layout — invariants that MUST hold (CI gate)

    func testWellesBuildingsDoNotOverlapEachOther() {
        let issues = WorldValidator.validate(.welles).buildingBuildingOverlaps
        XCTAssertTrue(issues.isEmpty,
                      "Authored buildings overlap:\n" + issues.map(\.message).joined(separator: "\n"))
    }

    func testWellesStoryPlacesAreAllOnRoads() {
        let issues = WorldValidator.validate(.welles).placesOffRoad
        XCTAssertTrue(issues.isEmpty,
                      "Story places off-road:\n" + issues.map(\.message).joined(separator: "\n"))
    }

    /// The renderer looks these landmarks up by id (and force-unwraps), so a
    /// renamed/missing id must fail here on CI rather than crash the app at launch.
    func testWellesHasExpectedLandmarkIds() {
        let ids = Set(WorldLayout.welles.buildings.map(\.id))
        for required in ["apt-western-n", "apt-western-s", "school", "restaurant-sunnyside",
                         "barber", "salon", "church", "library", "restaurant-corner"] {
            XCTAssertTrue(ids.contains(required),
                          "WorldLayout.welles is missing building id '\(required)'")
        }
        XCTAssertEqual(WorldLayout.welles.building(id: "library")?.center, Vec2(1020, 300))
        XCTAssertNil(WorldLayout.welles.building(id: "does-not-exist"))
    }

    // MARK: The deterministic streetwall (CI gate)

    func testStreetwallIsDeterministicAndFillsTheFrontages() {
        let a = WorldLayout.wellesStreetwall
        let b = WorldLayout.wellesStreetwall
        XCTAssertEqual(a, b, "streetwall must be reproducible (fixed data)")
        // Deterministic, so the count is exact — gap-fill around the landmark
        // anchors on the three frontages.
        XCTAssertEqual(a.count, 7, "streetwall building count changed unexpectedly")
        // Ids are unique (the renderer/validator key off them).
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
    }

    func testStreetwallIntroducesNoOverlaps() {
        let issues = WorldValidator.validate(.wellesComplete)
        // Landmarks were already overlap-free; the streetwall avoids them and itself.
        XCTAssertTrue(issues.buildingBuildingOverlaps.isEmpty,
                      "buildings overlap:\n" + issues.buildingBuildingOverlaps.map(\.message).joined(separator: "\n"))
        // No streetwall building sits on a road (only the known landmark overlaps remain).
        let wallOnRoad = issues.buildingRoadOverlaps.filter {
            if case let .buildingOverlapsRoad(b, _) = $0.kind { return b.hasPrefix("wall-") }
            return false
        }
        XCTAssertTrue(wallOnRoad.isEmpty,
                      "streetwall on roads:\n" + wallOnRoad.map(\.message).joined(separator: "\n"))
    }

    // MARK: No road runs under any building (CI gate)

    /// Every building — landmarks and streetwall — must sit in a block, never on a
    /// road. The landmarks that used to straddle the grid stubs (school, church,
    /// barber, corner restaurant) were moved into clear blocks; this keeps it that
    /// way and fails the build if anything is ever dropped on a road again.
    func testNoRoadRunsUnderAnyBuilding() {
        let overlaps = WorldValidator.validate(.wellesComplete).buildingRoadOverlaps
        XCTAssertTrue(overlaps.isEmpty,
                      "A road runs under a building — move it into a block:\n"
                        + overlaps.map { "  • " + $0.message }.joined(separator: "\n"))
    }
}
