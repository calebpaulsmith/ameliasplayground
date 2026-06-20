import XCTest
@testable import AmeliaCore

final class Vec2Tests: XCTestCase {
    func testArithmeticAndDistance() {
        let a = Vec2(1, 2), b = Vec2(4, 6)
        XCTAssertEqual(a + b, Vec2(5, 8))
        XCTAssertEqual(b - a, Vec2(3, 4))
        XCTAssertEqual(a.distance(to: b), 5, accuracy: 1e-9)
    }

    func testHeadingRoundTrip() {
        let v = Vec2.fromHeading(.pi / 2, length: 3)
        XCTAssertEqual(v.x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.z, 3, accuracy: 1e-9)
        XCTAssertEqual(v.heading, .pi / 2, accuracy: 1e-9)
    }
}

final class InputIntentsTests: XCTestCase {
    func testValuesAreClamped() {
        let i = InputIntents(steer: 5, throttle: 2, brake: -1)
        XCTAssertEqual(i.steer, 1)
        XCTAssertEqual(i.throttle, 1)
        XCTAssertEqual(i.brake, 0)
    }

    func testNeutralIsZeroed() {
        let n = InputIntents.neutral
        XCTAssertEqual(n.steer, 0)
        XCTAssertEqual(n.discreteTurn, .none)
        XCTAssertFalse(n.honkPressed)
    }
}

final class AssistLevelTests: XCTestCase {
    func testRecommendedDefaults() {
        XCTAssertEqual(AssistLevel.recommended(for: .siriRemote), .auto)
        XCTAssertEqual(AssistLevel.recommended(for: .controller), .assisted)
    }

    func testAuthorityAndAutoDrive() {
        XCTAssertTrue(AssistLevel.auto.autoDrives)
        XCTAssertFalse(AssistLevel.free.autoDrives)
        XCTAssertEqual(AssistLevel.auto.steeringAuthority, 0)
        XCTAssertEqual(AssistLevel.free.steeringAuthority, 1)
        XCTAssertGreaterThan(AssistLevel.free.maxSpeed, AssistLevel.auto.maxSpeed)
    }
}

final class SaveSlotTests: XCTestCase {
    func testAwardGrantAndComplete() {
        var s = SaveSlot()
        s.award(stars: 3)
        s.award(stars: -10)              // ignored
        s.grant(sticker: "first-day")
        s.grant(sticker: "first-day")    // de-duped
        s.markComplete(episode: "first-day")
        XCTAssertEqual(s.stars, 3)
        XCTAssertEqual(s.stickers, ["first-day"])
        XCTAssertTrue(s.hasCompleted(episode: "first-day"))
    }

    func testCodableRoundTrip() throws {
        var s = SaveSlot(name: "Mia", language: .es, assistLevel: .assisted)
        s.award(stars: 5)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SaveSlot.self, from: data)
        XCTAssertEqual(s, back)
    }
}

final class SaveStoreTests: XCTestCase {
    func testSaveLoadRoundTripAndCorruptFallback() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("amelia_test_\(UUID().uuidString).json")
        let store = SaveStore(fileURL: tmp)

        // Missing file -> fresh default.
        XCTAssertEqual(store.load(), SaveSlot())

        var slot = SaveSlot(name: "Pip", language: .es)
        slot.award(stars: 7)
        XCTAssertTrue(store.save(slot))
        XCTAssertEqual(store.load(), slot)

        // Corrupt file -> fresh default, never throws.
        try Data("not json".utf8).write(to: tmp)
        XCTAssertEqual(store.load(), SaveSlot())

        try? FileManager.default.removeItem(at: tmp)
    }
}

final class LocalizerTests: XCTestCase {
    private let loc = Localizer(table: [
        "hello": ["en": "Hello {name}", "es": "Hola {name}"],
        "enOnly": ["en": "Only English"]
    ])

    func testResolvesAndSubstitutes() {
        XCTAssertEqual(loc.string("hello", .es, vars: ["name": "Lola"]), "Hola Lola")
        XCTAssertEqual(loc.string("hello", .en, vars: ["name": "Lola"]), "Hello Lola")
    }

    func testFallsBackToEnglishThenId() {
        XCTAssertEqual(loc.string("enOnly", .es), "Only English")  // falls back to en
        XCTAssertEqual(loc.string("missing", .en), "missing")       // falls back to id
    }

    func testHasTranslation() {
        XCTAssertTrue(loc.hasTranslation("hello", .es))
        XCTAssertFalse(loc.hasTranslation("enOnly", .es))
    }
}

final class GameCoreTests: XCTestCase {
    func testAutoDriveRollsForward() {
        let core = GameCore(save: SaveSlot(assistLevel: .auto))
        core.autoThrottle = 1
        for _ in 0..<60 { core.tick(dt: 1.0 / 60.0, input: .neutral) }
        XCTAssertGreaterThan(core.bus.speed, 0)
        XCTAssertGreaterThan(core.bus.position.x, 0)   // heading 0 => +x
    }

    func testSpeedNeverExceedsAssistCap() {
        let core = GameCore(save: SaveSlot(assistLevel: .assisted))
        let input = InputIntents(throttle: 1)
        for _ in 0..<600 { core.tick(dt: 1.0 / 60.0, input: input) }
        XCTAssertLessThanOrEqual(core.bus.speed, AssistLevel.assisted.maxSpeed + 1e-6)
    }

    func testAutoDriveIgnoresPlayerSteering() {
        // In .auto, steeringAuthority is 0, so steering input must not turn the bus.
        let core = GameCore(save: SaveSlot(assistLevel: .auto))
        core.autoThrottle = 1
        let input = InputIntents(steer: 1)
        for _ in 0..<120 { core.tick(dt: 1.0 / 60.0, input: input) }
        XCTAssertEqual(core.bus.heading, 0, accuracy: 1e-6)
    }
}
