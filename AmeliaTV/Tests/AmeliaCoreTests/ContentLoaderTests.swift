import XCTest
@testable import AmeliaCore

/// Loads the *real* shipped content from AmeliaTV/Content/ and asserts it is
/// well-formed and fully bilingual. This is the unit-test mirror of the CI
/// content validator (Tools/validate_content.py) and the bilingual-by-
/// construction constraint (docs/tvos/PRODUCT_VISION.md).
final class ContentLoaderTests: XCTestCase {

    /// AmeliaTV/Content, located relative to this source file.
    private var contentDir: URL {
        URL(fileURLWithPath: #filePath)            // .../Tests/AmeliaCoreTests/ContentLoaderTests.swift
            .deletingLastPathComponent()           // .../Tests/AmeliaCoreTests
            .deletingLastPathComponent()           // .../Tests
            .deletingLastPathComponent()           // .../AmeliaTV
            .appendingPathComponent("Content")
    }

    func testContentLoadsAndIsConsistent() throws {
        let content = try ContentLoader.load(from: contentDir)

        XCTAssertFalse(content.places.isEmpty, "expected at least one place")
        XCTAssertFalse(content.passengers.isEmpty, "expected at least one passenger")
        XCTAssertFalse(content.episodes.isEmpty, "expected at least one episode")

        let placeIds = Set(content.places.map(\.id))
        // Every passenger's home place must exist.
        for p in content.passengers {
            XCTAssertTrue(placeIds.contains(p.homePlace),
                          "passenger \(p.id) references unknown place \(p.homePlace)")
        }
    }

    func testCollectiblesLoadAndAreWellFormed() throws {
        let content = try ContentLoader.load(from: contentDir)
        XCTAssertFalse(content.collectibles.isEmpty, "expected seeded collectibles to load")

        var ids = Set<String>()
        for c in content.collectibles {
            XCTAssertFalse(c.id.isEmpty, "collectible has an empty id")
            XCTAssertTrue(ids.insert(c.id).inserted, "duplicate collectible id \(c.id)")
            XCTAssertFalse(c.kind.isEmpty, "collectible \(c.id) has no kind")
            XCTAssertGreaterThanOrEqual(c.reward, 1, "collectible \(c.id) should reward ≥1 star")
        }
    }

    func testVehiclesLoadAndResolve() throws {
        let content = try ContentLoader.load(from: contentDir)
        XCTAssertFalse(content.vehicles.isEmpty, "expected the Rescue Team vehicles to load")

        let placeIds = Set(content.places.map(\.id))
        let loc = content.localizer
        let knownRoles: Set<String> = ["fire", "tow", "ambulance", "helicopter", "car"]
        for v in content.vehicles {
            XCTAssertTrue(placeIds.contains(v.homePlace),
                          "vehicle \(v.id) references unknown place \(v.homePlace)")
            XCTAssertTrue(knownRoles.contains(v.role), "vehicle \(v.id) has unknown role \(v.role)")
            XCTAssertTrue(loc.hasTranslation(v.nameId, .en) && loc.hasTranslation(v.nameId, .es),
                          "vehicle \(v.id) name \(v.nameId) is not bilingual")
            for line in v.lineIds ?? [] {
                XCTAssertTrue(loc.hasTranslation(line, .en) && loc.hasTranslation(line, .es),
                              "vehicle \(v.id) line \(line) is not bilingual")
            }
        }
    }

    func testEveryStringIsBilingual() throws {
        let content = try ContentLoader.load(from: contentDir)
        let loc = content.localizer
        for id in loc.ids {
            XCTAssertTrue(loc.hasTranslation(id, .en), "string \"\(id)\" missing English")
            XCTAssertTrue(loc.hasTranslation(id, .es), "string \"\(id)\" missing Spanish")
        }
    }

    func testEpisodeReferencesResolve() throws {
        let content = try ContentLoader.load(from: contentDir)
        let placeIds = Set(content.places.map(\.id))
        let passengerIds = Set(content.passengers.map(\.id))
        let loc = content.localizer

        for ep in content.episodes {
            XCTAssertTrue(loc.hasTranslation(ep.titleId, .en),
                          "episode \(ep.id) title not localized")
            for beat in ep.beats {
                switch beat {
                case let .say(lineId):
                    XCTAssertTrue(loc.hasTranslation(lineId, .en),
                                  "episode \(ep.id): say line \(lineId) not localized")
                case let .driveTo(placeId, arriveLineId):
                    XCTAssertTrue(placeIds.contains(placeId),
                                  "episode \(ep.id): driveTo unknown place \(placeId)")
                    if let l = arriveLineId {
                        XCTAssertTrue(loc.hasTranslation(l, .en),
                                      "episode \(ep.id): arrive line \(l) not localized")
                    }
                case let .pickup(passengerId, _):
                    XCTAssertTrue(passengerIds.contains(passengerId),
                                  "episode \(ep.id): pickup unknown passenger \(passengerId)")
                case let .dropoff(passengerId, placeId):
                    XCTAssertTrue(passengerIds.contains(passengerId),
                                  "episode \(ep.id): dropoff unknown passenger \(passengerId)")
                    XCTAssertTrue(placeIds.contains(placeId),
                                  "episode \(ep.id): dropoff unknown place \(placeId)")
                case let .choice(promptLineId, _):
                    XCTAssertTrue(loc.hasTranslation(promptLineId, .en),
                                  "episode \(ep.id): choice prompt \(promptLineId) not localized")
                case .lightStop, .cutscene, .reward:
                    break
                }
            }
        }
    }
}
