import XCTest
@testable import AmeliaCore

/// M2 — "honk → the world reacts." Verifies the reaction selection is stable,
/// varied across a crowd, and distance-gated — all without a GPU.
final class ReactionSystemTests: XCTestCase {
    private let sys = ReactionSystem()

    func testReactionIsDeterministic() {
        XCTAssertEqual(sys.reaction(forReactor: 3, honkCount: 2),
                       sys.reaction(forReactor: 3, honkCount: 2))
    }

    func testCrowdReactsInVariedWays() {
        // Across a handful of onlookers, we should see more than one reaction.
        let kinds = Set((0..<8).map { sys.reaction(forReactor: $0, honkCount: 0) })
        XCTAssertGreaterThan(kinds.count, 1)
    }

    func testReactionsChangeAcrossHonks() {
        let first = (0..<5).map { sys.reaction(forReactor: $0, honkCount: 0) }
        let second = (0..<5).map { sys.reaction(forReactor: $0, honkCount: 1) }
        XCTAssertNotEqual(first, second)
    }

    func testDistanceGate() {
        XCTAssertTrue(sys.reacts(atDistance: 100, radius: 400))
        XCTAssertFalse(sys.reacts(atDistance: 500, radius: 400))
    }
}
