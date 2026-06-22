import Foundation
import SpriteKit
import AmeliaCore

#if canImport(GameController)
import GameController
#endif

/// M1 — the drivable block. A GTA-style top-down town: the bus drives the road
/// network with a follow camera, buildings are drawn with faked height (¾ look),
/// and one procedural car shares the road. The *logic* (RoadNetwork, kinematics)
/// lives in the pure, unit-tested Core; this scene only renders it and feeds it
/// input (or a demo attract-drive so CI captures motion).
final class TownScene: SKScene {

    // World→screen: 1 world unit = `scale` points. The camera follows the bus,
    // so the town is bigger than the screen (you see a moving window of it).
    private let scale: CGFloat = 2.0

    private let net = RoadNetwork.demoTown
    private let cam = SKCameraNode()
    private let worldNode = SKNode()

    private struct Building { var center: Vec2; var size: CGSize; var height: CGFloat }
    private let buildings: [Building] = [
        Building(center: Vec2(-300, -200), size: CGSize(width: 200, height: 180), height: 90),
        Building(center: Vec2(300, -200), size: CGSize(width: 180, height: 150), height: 70),
        Building(center: Vec2(-300, 200), size: CGSize(width: 160, height: 190), height: 110),
        Building(center: Vec2(300, 200), size: CGSize(width: 210, height: 160), height: 80),
    ]

    private var bus = BusKinematics(position: Vec2(-300, -400), heading: 0,
                                    maxSpeed: 170, turnRate: 2.8)
    private var busNode = SKNode()
    private var busTarget = 1   // first head toward (600,-400), the +x corner

    private var car = BusKinematics(position: Vec2(600, 400), heading: .pi,
                                    maxSpeed: 130, turnRate: 2.8)
    private var carNode = SKNode()
    private var carTarget = 3   // first head toward (-600,400), going -x

    private var lastUpdate: TimeInterval = 0
    private var inputActive = false

    // MARK: - Setup

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.46, green: 0.73, blue: 0.42, alpha: 1) // grass
        addChild(worldNode)
        buildRoads()
        buildBuildings()

        busNode = makeVehicle(length: 120, width: 52,
                              body: SKColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1),
                              roof: SKColor(red: 0.95, green: 0.70, blue: 0.15, alpha: 1))
        busNode.zPosition = 10
        worldNode.addChild(busNode)

        carNode = makeVehicle(length: 92, width: 44,
                              body: SKColor(red: 0.85, green: 0.32, blue: 0.30, alpha: 1),
                              roof: SKColor(red: 0.70, green: 0.22, blue: 0.20, alpha: 1))
        carNode.zPosition = 10
        worldNode.addChild(carNode)

        addChild(cam)
        camera = cam
        syncNodes()
    }

    private func pt(_ v: Vec2) -> CGPoint { CGPoint(x: CGFloat(v.x) * scale, y: -CGFloat(v.z) * scale) }

    // MARK: - World build

    private func buildRoads() {
        for s in net.segments {
            // casing (slightly wider, darker) then the road surface
            worldNode.addChild(roadLine(s.a, s.b, width: CGFloat(s.width) * scale + 8,
                                        color: SKColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1), z: 0))
            worldNode.addChild(roadLine(s.a, s.b, width: CGFloat(s.width) * scale,
                                        color: SKColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1), z: 0.1))
            // dashed center line
            worldNode.addChild(centerDashes(s.a, s.b))
        }
    }

    private func roadLine(_ a: Vec2, _ b: Vec2, width: CGFloat, color: SKColor, z: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: pt(a)); path.addLine(to: pt(b))
        let n = SKShapeNode(path: path)
        n.strokeColor = color
        n.lineWidth = width
        n.lineCap = .round
        n.zPosition = z
        return n
    }

    private func centerDashes(_ a: Vec2, _ b: Vec2) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: pt(a)); path.addLine(to: pt(b))
        let dashed = path.copy(dashingWithPhase: 0, lengths: [18, 22])
        let n = SKShapeNode(path: dashed)
        n.strokeColor = SKColor(white: 0.95, alpha: 0.7)
        n.lineWidth = 3
        n.zPosition = 1
        return n
    }

    private func buildBuildings() {
        for b in buildings {
            let node = SKNode()
            node.position = pt(b.center)
            node.zPosition = 5
            let w = b.size.width * scale, d = b.size.height * scale

            // drop shadow for depth
            let shadow = SKShapeNode(rectOf: CGSize(width: w * 1.05, height: d * 1.05), cornerRadius: 6)
            shadow.fillColor = SKColor(white: 0, alpha: 0.16)
            shadow.strokeColor = .clear
            shadow.position = CGPoint(x: 10, y: -10)
            node.addChild(shadow)

            // footprint (ground level)
            let base = SKColor(red: 0.78, green: 0.74, blue: 0.66, alpha: 1)
            let side = SKColor(red: 0.62, green: 0.58, blue: 0.52, alpha: 1)
            let roof = SKColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1)
            let foot = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 4)
            foot.fillColor = base; foot.strokeColor = side; foot.lineWidth = 2
            node.addChild(foot)

            // side wall going "up" (screen +y) to fake height
            let wall = CGMutablePath()
            wall.move(to: CGPoint(x: -w / 2, y: d / 2))
            wall.addLine(to: CGPoint(x: -w / 2, y: d / 2 + b.height))
            wall.addLine(to: CGPoint(x: w / 2, y: d / 2 + b.height))
            wall.addLine(to: CGPoint(x: w / 2, y: d / 2))
            wall.closeSubpath()
            let wallNode = SKShapeNode(path: wall)
            wallNode.fillColor = side; wallNode.strokeColor = side; wallNode.lineWidth = 1
            node.addChild(wallNode)

            // roof on top
            let roofNode = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 4)
            roofNode.fillColor = roof; roofNode.strokeColor = base; roofNode.lineWidth = 2
            roofNode.position = CGPoint(x: 0, y: b.height)
            node.addChild(roofNode)

            worldNode.addChild(node)
        }
    }

    private func makeVehicle(length: CGFloat, width: CGFloat, body: SKColor, roof: SKColor) -> SKNode {
        let node = SKNode()
        // wheels (drawn first, underneath)
        for sx in [-length * 0.28, length * 0.28] {
            for sy in [-width * 0.55, width * 0.55] {
                let wheel = SKShapeNode(rectOf: CGSize(width: length * 0.18, height: width * 0.16), cornerRadius: 3)
                wheel.fillColor = SKColor(white: 0.12, alpha: 1); wheel.strokeColor = .clear
                wheel.position = CGPoint(x: sx, y: sy)
                node.addChild(wheel)
            }
        }
        let chassis = SKShapeNode(rectOf: CGSize(width: length, height: width), cornerRadius: 10)
        chassis.fillColor = body
        chassis.strokeColor = SKColor(white: 0, alpha: 0.25)
        chassis.lineWidth = 2
        node.addChild(chassis)
        // roof patch toward the back, windshield toward the front (+x)
        let roofPatch = SKShapeNode(rectOf: CGSize(width: length * 0.5, height: width * 0.74), cornerRadius: 6)
        roofPatch.fillColor = roof; roofPatch.strokeColor = .clear
        roofPatch.position = CGPoint(x: -length * 0.1, y: 0)
        node.addChild(roofPatch)
        let windshield = SKShapeNode(rectOf: CGSize(width: length * 0.16, height: width * 0.66), cornerRadius: 4)
        windshield.fillColor = SKColor(red: 0.6, green: 0.8, blue: 0.95, alpha: 1); windshield.strokeColor = .clear
        windshield.position = CGPoint(x: length * 0.34, y: 0)
        node.addChild(windshield)
        return node
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime
        guard dt > 0 else { return }

        driveBus(dt: dt)
        driveCar(dt: dt)
        syncNodes()
        cam.position = busNode.position   // follow camera
    }

    private func driveBus(dt: Double) {
        if let input = controllerInput() {
            inputActive = true
            applyMove(&bus, throttle: input.throttle, steer: input.steer, dt: dt)
            return
        }
        if inputActive { return }
        // Demo attract-drive: follow the outer loop, easing off into corners.
        let loop = RoadNetwork.demoLoop
        let target = loop[busTarget % loop.count]
        let dist = bus.position.distance(to: target)
        if dist < 70 { busTarget = (busTarget + 1) % loop.count }
        let throttle = dist < 180 ? 0.35 : 1.0
        applyMove(&bus, throttle: throttle, steer: bus.steer(toward: target), dt: dt)
    }

    private func driveCar(dt: Double) {
        let loop = RoadNetwork.demoLoop
        let target = loop[carTarget % loop.count]
        let dist = car.position.distance(to: target)
        if dist < 70 { carTarget = (carTarget + 1) % loop.count }
        let throttle = dist < 180 ? 0.4 : 1.0
        applyMove(&car, throttle: throttle, steer: car.steer(toward: target), dt: dt)
    }

    /// Apply kinematics, then refuse moves that would enter a building (collision).
    private func applyMove(_ v: inout BusKinematics, throttle: Double, steer: Double, dt: Double) {
        let before = v.position
        v.update(throttle: throttle, steer: steer, dt: dt)
        if collides(v.position) {
            v.position = before
            v.speed = 0
        }
    }

    private func collides(_ p: Vec2) -> Bool {
        for b in buildings {
            let hw = b.size.width / 2, hd = b.size.height / 2
            if abs(p.x - b.center.x) < Double(hw) && abs(p.z - b.center.z) < Double(hd) {
                return true
            }
        }
        return false
    }

    private func syncNodes() {
        busNode.position = pt(bus.position)
        busNode.zRotation = -CGFloat(bus.heading)   // screen maps world z to -y
        carNode.position = pt(car.position)
        carNode.zRotation = -CGFloat(car.heading)
    }

    // MARK: - Input

    private func controllerInput() -> (throttle: Double, steer: Double)? {
        #if canImport(GameController)
        for c in GCController.controllers() {
            if let g = c.extendedGamepad {
                let x = Double(g.leftThumbstick.xAxis.value)
                let y = Double(g.leftThumbstick.yAxis.value)
                if abs(x) > 0.12 || abs(y) > 0.12 { return (y, x) }
                let dx = Double(g.dpad.xAxis.value), dy = Double(g.dpad.yAxis.value)
                if abs(dx) > 0.12 || abs(dy) > 0.12 { return (dy, dx) }
            } else if let m = c.microGamepad {
                m.reportsAbsoluteDpadValues = true
                let x = Double(m.dpad.xAxis.value), y = Double(m.dpad.yAxis.value)
                if abs(x) > 0.12 || abs(y) > 0.12 { return (y, x) }
            }
        }
        #endif
        return nil
    }
}
