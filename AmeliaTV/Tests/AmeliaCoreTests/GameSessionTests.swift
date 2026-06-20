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

    func testNoTargetDoesNotMoveTheBus() {
        // With no active episode/target, Auto-Drive holds position (no drifting).
        let session = GameSession(content: GameContent(), save: SaveSlot(assistLevel: .auto))
        for _ in 0..<120 { session.tick(dt: 1.0 / 60, input: .neutral) }
        XCTAssertEqual(session.bus.position.x, 0, accuracy: 0.01)
        XCTAssertEqual(session.bus.position.z, 0, accuracy: 0.01)
    }
}
