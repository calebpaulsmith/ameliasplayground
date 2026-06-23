import XCTest
@testable import AmeliaCore

/// M3 CH-01 — the brake-in-time challenge. Verifies the meter, scoring, and the
/// no-harsh-failure behaviour, all without a GPU.
final class QuickStopChallengeTests: XCTestCase {

    func testStoppingInTimeScores() {
        var c = QuickStopChallenge(duration: 2, stopSpeed: 8)
        c.arm()
        XCTAssertEqual(c.state, .running)
        c.update(dt: 0.3, busSpeed: 120)      // still rolling
        XCTAssertEqual(c.state, .running)
        c.update(dt: 0.1, busSpeed: 0)        // stopped in time
        XCTAssertEqual(c.state, .success)
        XCTAssertGreaterThan(c.score, 0)
    }

    func testStoppingSoonerScoresMore() {
        var quick = QuickStopChallenge(duration: 2, stopSpeed: 8); quick.arm()
        quick.update(dt: 0.2, busSpeed: 0)
        var slow = QuickStopChallenge(duration: 2, stopSpeed: 8); slow.arm()
        slow.update(dt: 1.6, busSpeed: 100)   // drain most of the meter
        slow.update(dt: 0.1, busSpeed: 0)
        XCTAssertGreaterThan(quick.score, slow.score)
    }

    func testMeterDrainsAndMissesWithoutStopping() {
        var c = QuickStopChallenge(duration: 1, stopSpeed: 8); c.arm()
        c.update(dt: 0.5, busSpeed: 100)
        XCTAssertEqual(c.meter, 0.5, accuracy: 1e-9)
        c.update(dt: 0.6, busSpeed: 100)      // meter empties
        XCTAssertEqual(c.state, .missed)
    }

    func testMissCanRetry() {
        var c = QuickStopChallenge(duration: 1, stopSpeed: 8); c.arm()
        c.update(dt: 2, busSpeed: 100)
        XCTAssertEqual(c.state, .missed)
        c.reset(); c.arm()
        XCTAssertEqual(c.state, .running)
        XCTAssertEqual(c.meter, 1, accuracy: 1e-9)
    }

    func testIdleIgnoresUpdates() {
        var c = QuickStopChallenge()
        c.update(dt: 1, busSpeed: 0)
        XCTAssertEqual(c.state, .idle)
    }
}
