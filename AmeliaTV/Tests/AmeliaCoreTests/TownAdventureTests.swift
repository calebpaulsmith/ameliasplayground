import XCTest
@testable import AmeliaCore

/// A minimal `EpisodeWorld` that "drives" itself: whenever the runner sets a
/// place target, it teleports the bus onto it (stopped), simulating the bus
/// arriving. Lets us play the whole town ride headlessly — no GPU, no scene.
private final class DrivingWorld: EpisodeWorld {
    var busPosition: Vec2 = Vec2(-300, -400)
    var busSpeed: Double = 0
    let map = TownMap.demo
    var currentTarget: EpisodeTarget?

    func position(ofPlace placeId: String) -> Vec2? { map.position(ofPlace: placeId) }
    func position(ofLight lightId: String) -> Vec2? { nil }
    func lightState(_ lightId: String) -> TrafficLight.State { .green }
    func consumeDiscreteTurn() -> InputIntents.DiscreteTurn { .none }

    /// Move the bus to the active target (as if it drove there and stopped).
    func arriveAtTarget() {
        if let t = currentTarget { busPosition = t.position; busSpeed = 0 }
    }
}

final class TownAdventureTests: XCTestCase {

    func testTownFirstRidePicksUpDropsOffAndRewards() {
        var events: [EpisodeEvent] = []
        let world = DrivingWorld()
        let runner = EpisodeRunner(episode: .townFirstRide, world: world) { event in
            events.append(event)
            if case let .setTarget(target) = event { world.currentTarget = target }
        }

        runner.start()
        // Drive the ride to completion: each tick, snap the bus onto whatever the
        // runner is currently asking us to drive to, then advance time generously
        // so the say/board/drop dwells elapse.
        for _ in 0..<300 where !runner.finished {
            world.arriveAtTarget()
            runner.update(dt: 0.2)
        }

        XCTAssertTrue(runner.finished, "the ride should run to completion")
        XCTAssertTrue(events.contains(.board(passengerId: "pip")), "Pip should board at the stop")
        XCTAssertTrue(events.contains(.drop(passengerId: "pip", placeId: "school")),
                      "Pip should be dropped at the school")
        XCTAssertTrue(events.contains(.reward(stars: 3, stickerId: "first-day")),
                      "the ride should award the first-day reward")
        XCTAssertEqual(events.last, .completed)
    }

    func testTownFirstRideArriveLinesAreSpoken() {
        var spoken: [String] = []
        let world = DrivingWorld()
        let runner = EpisodeRunner(episode: .townFirstRide, world: world) { event in
            if case let .speak(lineId, _) = event { spoken.append(lineId) }
            if case let .setTarget(target) = event { world.currentTarget = target }
        }
        runner.start()
        for _ in 0..<300 where !runner.finished {
            world.arriveAtTarget()
            runner.update(dt: 0.2)
        }
        // The guiding voice names the stop and the school, and welcomes Pip aboard.
        XCTAssertTrue(spoken.contains("m.pickup"))
        XCTAssertTrue(spoken.contains("m.allAboard"))
        XCTAssertTrue(spoken.contains("m.dropSchool"))
    }

    func testTownMapPlacesSitOnTheRoadNetwork() {
        // Every story stop must be drivable — i.e. on a road — or the bus could
        // never stop there. Guards against authoring a place out in the grass.
        let net = RoadNetwork.demoTown
        for (id, pos) in TownMap.demo.places {
            XCTAssertTrue(net.isOnRoad(pos), "town place \"\(id)\" is not on a road")
        }
    }
}
