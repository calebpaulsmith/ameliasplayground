import XCTest
@testable import AmeliaCore

/// The pure animation math behind the "character life" pass — verified headlessly
/// (no GPU) so the render layer can rely on it.
final class EasingTests: XCTestCase {

    func testSmoothedConvergesAndStaysBetween() {
        var v = 0.0
        let target = 1.0
        for _ in 0..<600 {                       // ~10s at 60fps
            let prev = v
            v = Easing.smoothed(v, toward: target, rate: 6, dt: 1.0 / 60)
            // Monotonic toward the target for a step input, never overshoots.
            XCTAssertGreaterThanOrEqual(v, prev)
            XCTAssertLessThanOrEqual(v, target + 1e-9)
        }
        XCTAssertEqual(v, target, accuracy: 0.001, "smoothing did not settle on the target")
    }

    func testSmoothedIsAStableNoOpForZeroOrNegativeStep() {
        XCTAssertEqual(Easing.smoothed(0.3, toward: 1, rate: 6, dt: 0), 0.3)
        XCTAssertEqual(Easing.smoothed(0.3, toward: 1, rate: 0, dt: 0.016), 0.3)
    }

    func testLerpClamps() {
        XCTAssertEqual(Easing.lerp(0, 10, 0.5), 5, accuracy: 1e-9)
        XCTAssertEqual(Easing.lerp(0, 10, -1), 0, accuracy: 1e-9)
        XCTAssertEqual(Easing.lerp(0, 10, 2), 10, accuracy: 1e-9)
    }

    func testSpringSettlesOnTarget() {
        var s = Spring(value: 0)
        for _ in 0..<600 { s.step(toward: 1, dt: 1.0 / 60) }
        XCTAssertEqual(s.value, 1, accuracy: 0.01, "spring did not settle on the target")
        XCTAssertEqual(s.velocity, 0, accuracy: 0.01, "spring never came to rest")
    }

    func testUnderdampedSpringOvershootsThenReturns() {
        // A nudge from rest should bounce past zero at least once, then settle.
        var s = Spring(value: 0)
        s.nudge(8)
        var maxValue = 0.0
        for _ in 0..<600 {
            s.step(toward: 0, dt: 1.0 / 60)
            maxValue = max(maxValue, s.value)
        }
        XCTAssertGreaterThan(maxValue, 0.05, "an underdamped nudge should visibly overshoot")
        XCTAssertEqual(s.value, 0, accuracy: 0.01, "spring did not return to rest")
    }
}
