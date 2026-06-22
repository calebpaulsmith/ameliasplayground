import XCTest
@testable import AmeliaCore

/// M1 — the drivable block. Verifies the road network geometry and the bus
/// kinematics in pure Swift (no GPU), so driving logic is caught by tests and
/// only the *look* needs a human + a CI capture.
final class DrivableWorldTests: XCTestCase {

    // MARK: RoadNetwork

    func testPointOnRoadCenterlineIsOnRoad() {
        let net = RoadNetwork.demoTown
        // Middle of the top loop segment (z = -400).
        XCTAssertTrue(net.isOnRoad(Vec2(0, -400)))
        XCTAssertEqual(net.distanceToRoad(Vec2(0, -400)), 0, accuracy: 1e-6)
    }

    func testPointInsideABlockIsOffRoad() {
        let net = RoadNetwork.demoTown
        // Center of a block, well away from any road.
        XCTAssertFalse(net.isOnRoad(Vec2(-300, -200)))
        XCTAssertGreaterThan(net.distanceToRoad(Vec2(-300, -200)), 90)
    }

    func testRoadHasWidth() {
        let net = RoadNetwork.demoTown
        // Just inside the 90-wide top road (±45 from centerline).
        XCTAssertTrue(net.isOnRoad(Vec2(0, -400 + 40)))
        // Just outside it.
        XCTAssertFalse(net.isOnRoad(Vec2(0, -400 + 60)))
    }

    func testSegmentClosestClampsToEndpoints() {
        let s = RoadSegment(a: Vec2(0, 0), b: Vec2(100, 0), width: 90)
        // Beyond b: closest point clamps to b.
        let r = s.closest(to: Vec2(200, 0))
        XCTAssertEqual(r.point, Vec2(100, 0))
        XCTAssertEqual(r.distance, 100, accuracy: 1e-6)
    }

    // MARK: BusKinematics

    func testThrottleAcceleratesAndMovesForward() {
        var bus = BusKinematics(position: .zero, heading: 0)   // facing +x
        for _ in 0..<60 { bus.update(throttle: 1, steer: 0, dt: 1.0 / 60) }
        XCTAssertGreaterThan(bus.speed, 0)
        XCTAssertGreaterThan(bus.position.x, 1)        // moved along +x
        XCTAssertEqual(bus.position.z, 0, accuracy: 1e-6)
    }

    func testCoastingDecelerates() {
        var bus = BusKinematics(position: .zero, heading: 0, speed: 200)
        bus.update(throttle: 0, steer: 0, dt: 0.5)
        XCTAssertLessThan(bus.speed, 200)
    }

    func testSteeringTurnsHeadingWhileMoving() {
        var bus = BusKinematics(position: .zero, heading: 0, speed: 200)
        let h0 = bus.heading
        bus.update(throttle: 1, steer: 1, dt: 0.2)
        XCTAssertNotEqual(bus.heading, h0)
    }

    func testParkedBusDoesNotSteer() {
        var bus = BusKinematics(position: .zero, heading: 0, speed: 0)
        bus.update(throttle: 0, steer: 1, dt: 0.2)
        XCTAssertEqual(bus.heading, 0, accuracy: 1e-9)
    }

    func testSteerTowardTargetPointsTheRightWay() {
        let bus = BusKinematics(position: .zero, heading: 0)  // facing +x
        // Target up and to the +z side → steer toward increasing heading (+).
        XCTAssertGreaterThan(bus.steer(toward: Vec2(10, 10)), 0)
        // Target toward -z → negative steer.
        XCTAssertLessThan(bus.steer(toward: Vec2(10, -10)), 0)
    }
}
