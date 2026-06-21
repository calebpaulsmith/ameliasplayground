import XCTest
@testable import AmeliaCore

/// End-to-end test of the playable slice logic: loads the real shipped content
/// and plays the "first-day" episode to completion under Auto-Drive, asserting
/// the bus actually reaches every target, the passenger boards, and rewards land.
final class GameSessionTests: XCTestCase {

    private var contentDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Content")
    }

    func testFirstDayPlaythroughCompletesUnderAutoDrive() throws {
        let content = try ContentLoader.load(from: contentDir)
        var persisted: SaveSlot?
        let session = GameSession(
            content: content,
            save: SaveSlot(language: .en, assistLevel: .auto),
            speaker: nil,
            persist: { persisted = $0 }
        )

        session.start(episodeId: "first-day", at: Vec2.zero, heading: 0)

        var boardedPip = false
        let dt = 1.0 / 60.0
        let maxSteps = 60 * 240   // 4 minutes of simulated time — generous budget

        var steps = 0
        while !session.finished && steps < maxSteps {
            // The child "presses right" at the fork; harmless at other times.
            session.tick(dt: dt, input: InputIntents(discreteTurn: .right))
            if session.currentPassengerId == "pip" { boardedPip = true }
            steps += 1
        }

        XCTAssertTrue(session.finished, "episode did not complete within the step budget")
        XCTAssertTrue(boardedPip, "passenger never boarded")
        XCTAssertGreaterThanOrEqual(session.save.stars, 3, "reward stars not awarded")
        XCTAssertTrue(session.save.stickers.contains("first-day"), "sticker not granted")
        XCTAssertTrue(session.save.completedEpisodes.contains("first-day"), "episode not marked complete")
        XCTAssertEqual(persisted?.completedEpisodes, session.save.completedEpisodes,
                       "progress was not persisted on completion")
    }

    func testDrivePromptShowsStopAtRedLightAndGoOtherwise() throws {
        let content = try ContentLoader.load(from: contentDir)
        let session = GameSession(content: content,
                                  save: SaveSlot(language: .en, assistLevel: .auto))
        session.start(episodeId: "first-day", at: Vec2.zero, heading: 0)

        // Drive until the bus is asked to obey a red light, capturing both states.
        var sawStop = false
        var sawGo = false
        let dt = 1.0 / 60.0
        var steps = 0
        while !session.finished && steps < 60 * 240 {
            session.tick(dt: dt, input: InputIntents(discreteTurn: .right))
            switch session.drivePrompt {
            case .stop: sawStop = true
            case .go:   sawGo = true
            }
            steps += 1
        }

        XCTAssertTrue(sawStop, "HUD never showed STOP while waiting at a red light")
        XCTAssertTrue(sawGo, "HUD never showed GO during normal driving")
    }

    func testPassengerPlanReflectsEpisodeBeats() throws {
        let content = try ContentLoader.load(from: contentDir)
        let session = GameSession(content: content, save: SaveSlot(language: .en, assistLevel: .auto))
        XCTAssertNil(session.passengerPlan, "no plan before an episode starts")

        session.start(episodeId: "first-day")
        let plan = session.passengerPlan
        XCTAssertEqual(plan?.passengerId, "pip")
        XCTAssertEqual(plan?.pickupPlaceId, "stopA")
        XCTAssertEqual(plan?.dropoffPlaceId, "park")
    }

    func testRewardPlanReadsTheEpisodeRewardBeat() throws {
        let content = try ContentLoader.load(from: contentDir)
        let session = GameSession(content: content, save: SaveSlot(language: .en, assistLevel: .auto))
        XCTAssertNil(session.rewardPlan, "no reward plan before an episode starts")

        session.start(episodeId: "first-day")
        let reward = session.rewardPlan
        XCTAssertEqual(reward?.stars, 3, "reward stars should come from the episode's reward beat")
        XCTAssertEqual(reward?.stickerId, "first-day", "reward sticker should come from the reward beat")
    }

    func testNoTargetDoesNotMoveTheBus() {
        // With no active episode/target, Auto-Drive holds position (no drifting).
        let session = GameSession(content: GameContent(), save: SaveSlot(assistLevel: .auto))
        for _ in 0..<120 { session.tick(dt: 1.0 / 60, input: .neutral) }
        XCTAssertEqual(session.bus.position.x, 0, accuracy: 0.01)
        XCTAssertEqual(session.bus.position.z, 0, accuracy: 0.01)
    }
}
