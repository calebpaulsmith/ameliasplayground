import XCTest
@testable import AmeliaCore

// MARK: - Navigation

final class RouteGraphTests: XCTestCase {
    /// A tiny 3-node L shape:  A(0,0) — B(10,0) — C(10,10)
    private func lGraph() -> RouteGraph {
        var g = RouteGraph()
        g.addNode("A", at: Vec2(0, 0))
        g.addNode("B", at: Vec2(10, 0))
        g.addNode("C", at: Vec2(10, 10))
        g.addEdge("A", "B")
        g.addEdge("B", "C")
        return g
    }

    func testShortestPath() {
        let g = lGraph()
        XCTAssertEqual(g.shortestPath(from: "A", to: "C"), ["A", "B", "C"])
        XCTAssertEqual(g.shortestPath(from: "A", to: "A"), ["A"])
    }

    func testNearestNode() {
        let g = lGraph()
        XCTAssertEqual(g.nearestNode(to: Vec2(9, 1)), "B")
        XCTAssertEqual(g.nearestNode(to: Vec2(11, 9)), "C")
    }

    func testTurnCuesFromOriginFacingPositiveX() {
        let g = lGraph()
        // Facing +x (heading 0): heading increases to the right.
        XCTAssertEqual(g.turnCue(at: Vec2(0, 0), heading: 0, toward: "B"), .straight)
        // Node directly +z is a right turn; -z is a left turn.
        var h = RouteGraph()
        h.addNode("R", at: Vec2(0, 10))
        h.addNode("L", at: Vec2(0, -10))
        h.addNode("U", at: Vec2(-10, 0))
        XCTAssertEqual(h.turnCue(at: .zero, heading: 0, toward: "R"), .right)
        XCTAssertEqual(h.turnCue(at: .zero, heading: 0, toward: "L"), .left)
        XCTAssertEqual(h.turnCue(at: .zero, heading: 0, toward: "U"), .uTurn)
    }

    func testArriveCue() {
        var g = RouteGraph()
        g.addNode("X", at: Vec2(3, 0))
        XCTAssertEqual(g.turnCue(at: .zero, heading: 0, toward: "X", arriveRadius: 8), .arrive)
    }
}

// MARK: - Traffic light

final class TrafficLightTests: XCTestCase {
    func testCyclesGreenYellowRed() {
        var light = TrafficLight(id: "t")
        XCTAssertEqual(light.state, .green)
        XCTAssertEqual(light.cycleLength, 14)
        light.update(dt: 6.5)          // 6..8 => yellow
        XCTAssertEqual(light.state, .yellow)
        light.update(dt: 2.0)          // 8.5 => red (8..14)
        XCTAssertEqual(light.state, .red)
        light.update(dt: 6.0)          // 14.5 wraps => green
        XCTAssertEqual(light.state, .green)
    }

    func testPhaseOffsetStartsRed() {
        let light = TrafficLight(id: "t", phase: 9)   // 9 is within red band
        XCTAssertEqual(light.state, .red)
    }
}

// MARK: - Dialogue

final class DialogueDirectorTests: XCTestCase {
    final class SpySpeaker: LineSpeaker {
        var spoken: [(String, Language)] = []
        var stops = 0
        func speak(_ text: String, language: Language) { spoken.append((text, language)) }
        func stopSpeaking() { stops += 1 }
    }

    private func director(_ spy: SpySpeaker, _ lang: Language = .en) -> DialogueDirector {
        let loc = Localizer(table: [
            "hello": ["en": "Hello {name}", "es": "Hola {name}"],
            "bye": ["en": "Bye", "es": "Adiós"]
        ])
        return DialogueDirector(localizer: loc, language: lang, speaker: spy)
    }

    func testResolvesAndSpeaks() {
        let spy = SpySpeaker()
        let d = director(spy, .es)
        XCTAssertEqual(d.play("hello", vars: ["name": "Pip"]), "Hola Pip")
        XCTAssertEqual(spy.spoken.count, 1)
        XCTAssertEqual(spy.spoken[0].0, "Hola Pip")
        XCTAssertEqual(d.currentSubtitle, "Hola Pip")
    }

    func testDedupesImmediateRepeat() {
        let spy = SpySpeaker()
        let d = director(spy)
        d.play("bye")
        d.play("bye")               // ignored
        d.play("bye", force: true)  // forced
        XCTAssertEqual(spy.spoken.count, 2)
    }
}

// MARK: - Episode runner

private final class MockWorld: EpisodeWorld {
    var busPosition: Vec2 = .zero
    var busSpeed: Double = 0
    var places: [String: Vec2]
    var lights: [String: Vec2]
    var lightStates: [String: TrafficLight.State] = [:]
    var queuedTurn: InputIntents.DiscreteTurn = .none

    init(places: [String: Vec2], lights: [String: Vec2] = [:]) {
        self.places = places
        self.lights = lights
    }
    func position(ofPlace placeId: String) -> Vec2? { places[placeId] }
    func position(ofLight lightId: String) -> Vec2? { lights[lightId] }
    func lightState(_ lightId: String) -> TrafficLight.State { lightStates[lightId] ?? .green }
    func consumeDiscreteTurn() -> InputIntents.DiscreteTurn {
        defer { queuedTurn = .none }
        return queuedTurn
    }
}

final class EpisodeRunnerTests: XCTestCase {

    private func makeEpisode() -> Episode {
        Episode(id: "t", titleId: "episode.firstDay.title", neighborhood: "n", beats: [
            .say(lineId: "m.dawn"),
            .driveTo(placeId: "stopA", arriveLineId: "m.pickup"),
            .pickup(passengerId: "pip", atStop: "stopA"),
            .lightStop(lightId: "light1"),
            .choice(promptLineId: "m.chooseRight", correct: .right),
            .driveTo(placeId: "park", arriveLineId: nil),
            .reward(stars: 3, stickerId: "first-day")
        ])
    }

    func testHappyPathRunEmitsExpectedFlow() {
        var events: [EpisodeEvent] = []
        let world = MockWorld(places: ["stopA": Vec2(44, 0), "park": Vec2(88, 44)],
                              lights: ["light1": Vec2(66, 22)])
        let runner = EpisodeRunner(episode: makeEpisode(), world: world) { events.append($0) }

        runner.start()
        XCTAssertEqual(events.first, .speak(lineId: "m.dawn", vars: [:]))

        // Finish the "say" dwell -> targets the bus to the stop.
        runner.update(dt: 2.5)
        XCTAssertTrue(events.contains(.setTarget(EpisodeTarget(
            kind: .place, id: "stopA", position: Vec2(44, 0), radius: 12, requireStop: true))))

        // Arrive at the stop, stopped -> arrive line + board.
        world.busPosition = Vec2(44, 0); world.busSpeed = 0
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.speak(lineId: "m.pickup", vars: [:])))
        XCTAssertTrue(events.contains(.board(passengerId: "pip")))

        // Board dwell -> targets the light.
        runner.update(dt: 2.3)
        XCTAssertTrue(events.contains(.setTarget(EpisodeTarget(
            kind: .light, id: "light1", position: Vec2(66, 22), radius: 12, requireStop: true))))

        // Drive to the light, red, stopped -> waits (no advance).
        world.busPosition = Vec2(66, 22); world.busSpeed = 0
        world.lightStates["light1"] = .red
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.speak(lineId: "light.redStop", vars: [:])))

        // Light turns green after stopping -> praise + sparkle + choice prompt.
        world.lightStates["light1"] = .green
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.speak(lineId: "light.goodStop", vars: [:])))
        XCTAssertTrue(events.contains(.awaitChoice(promptLineId: "m.chooseRight")))

        // Wrong turn is gently re-prompted, not punished.
        world.queuedTurn = .left
        let beforeWrong = events.count
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.speak(lineId: "nav.tryOtherWay", vars: [:])))
        XCTAssertFalse(runner.finished)
        XCTAssertGreaterThan(events.count, beforeWrong)

        // Correct turn -> advance to drive to the park.
        world.queuedTurn = .right
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.setTarget(EpisodeTarget(
            kind: .place, id: "park", position: Vec2(88, 44), radius: 12, requireStop: true))))

        // Arrive at the park -> reward + completion.
        world.busPosition = Vec2(88, 44); world.busSpeed = 0
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.reward(stars: 3, stickerId: "first-day")))
        XCTAssertEqual(events.last, .completed)
        XCTAssertTrue(runner.finished)
    }

    func testNoFailureWhenLightAlreadyGreen() {
        // If the light is green on arrival, the bus simply proceeds (no stuck state).
        var events: [EpisodeEvent] = []
        let world = MockWorld(places: ["stopA": Vec2(0, 0)], lights: ["light1": Vec2(0, 0)])
        let ep = Episode(id: "t", titleId: "episode.firstDay.title", neighborhood: "n",
                         beats: [.lightStop(lightId: "light1"), .reward(stars: 1, stickerId: nil)])
        let runner = EpisodeRunner(episode: ep, world: world) { events.append($0) }
        runner.start()
        world.busPosition = .zero; world.busSpeed = 0
        world.lightStates["light1"] = .green
        runner.update(dt: 1.0 / 60)
        XCTAssertTrue(events.contains(.speak(lineId: "light.greenGo", vars: [:])))
        XCTAssertTrue(runner.finished)
    }
}

// MARK: - Content: lights resolve

final class LightsContentTests: XCTestCase {
    private var contentDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Content")
    }

    func testLightStopReferencesResolve() throws {
        let content = try ContentLoader.load(from: contentDir)
        let lightIds = Set(content.lights.map(\.id))
        for ep in content.episodes {
            for beat in ep.beats {
                if case let .lightStop(lightId) = beat {
                    XCTAssertTrue(lightIds.contains(lightId),
                                  "episode \(ep.id) references unknown light \(lightId)")
                }
            }
        }
    }
}
