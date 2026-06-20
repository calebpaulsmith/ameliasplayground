import XCTest
@testable import AmeliaCore

/// A2-13 — verifies the slice emits a warm, complete set of audio cues as it
/// plays, using the same headless playthrough the gameplay tests use. The Core
/// only decides *which* cue fires when; the app synthesizes the actual sound.
final class AudioTests: XCTestCase {

    private var contentDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Content")
    }

    /// Records everything the session asks the audio layer to do.
    private final class SpySound: SoundPlayer {
        private(set) var cues: [SoundCue] = []
        private(set) var themes: [MusicTheme] = []
        private(set) var stopAllCount = 0
        func play(_ cue: SoundCue) { cues.append(cue) }
        func setMusic(_ theme: MusicTheme) { themes.append(theme) }
        func stopAll() { stopAllCount += 1 }
    }

    func testSlicePlaythroughEmitsWarmAudioCues() throws {
        let content = try ContentLoader.load(from: contentDir)
        let spy = SpySound()
        let session = GameSession(content: content,
                                  save: SaveSlot(language: .en, assistLevel: .auto),
                                  sound: spy)

        session.start(episodeId: "first-day", at: .zero, heading: 0)

        let dt = 1.0 / 60.0
        var steps = 0
        while !session.finished && steps < 60 * 240 {
            session.tick(dt: dt, input: InputIntents(discreteTurn: .right))
            steps += 1
        }
        XCTAssertTrue(session.finished, "episode did not complete within the step budget")

        // Music bed: opens on the driving loop, ends on the reward bed.
        XCTAssertEqual(spy.themes.first, .driving, "did not start the driving music")
        XCTAssertEqual(spy.themes.last, .reward, "did not switch to the reward music on completion")

        // The warm SFX set all fired across the loop (horn off the line, door on
        // board + drop, a star sparkle, a green-light/good-stop chime, and the
        // completion + new-sticker flourishes).
        for expected: SoundCue in [.horn, .doorOpen, .doorClose, .starSparkle, .chime, .reward, .rewardSticker] {
            XCTAssertTrue(spy.cues.contains(expected), "expected cue \(expected) never played")
        }
    }

    func testWrongTurnAtForkPlaysGentleBumpAndNeverFails() throws {
        let content = try ContentLoader.load(from: contentDir)
        let spy = SpySound()
        let session = GameSession(content: content,
                                  save: SaveSlot(language: .en, assistLevel: .auto),
                                  sound: spy)

        session.start(episodeId: "first-day", at: .zero, heading: 0)

        // Auto-drive to the fork without pressing anything.
        let dt = 1.0 / 60.0
        var steps = 0
        while !session.awaitingChoice && steps < 60 * 240 {
            session.tick(dt: dt, input: .neutral)
            steps += 1
        }
        XCTAssertTrue(session.awaitingChoice, "never reached the fork choice")

        // A wrong (left) turn at the right-turn fork should give a soft bump and a
        // gentle re-prompt — never end or "fail" the episode.
        session.tick(dt: dt, input: InputIntents(discreteTurn: .left))
        XCTAssertTrue(spy.cues.contains(.bump), "a wrong turn did not play the gentle bump")
        XCTAssertFalse(session.finished, "a wrong turn must never end the episode")
    }
}
