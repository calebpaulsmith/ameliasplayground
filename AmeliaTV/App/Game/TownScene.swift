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

    // The bus drives the loop clockwise; the car drives it the other way, so the
    // two pass on opposite sides (real two-way traffic) instead of tailgating.
    private let busLoop = RoadNetwork.demoLoop
    private let carLoop = Array(RoadNetwork.demoLoop.reversed())

    private var bus = BusKinematics(position: Vec2(-300, -400), heading: 0,
                                    maxSpeed: 170, turnRate: 2.8)
    private var busNode = SKNode()
    private var busTarget = 1   // first head toward (600,-400), the +x corner

    private var car = BusKinematics(position: Vec2(600, 400), heading: -.pi / 2,
                                    maxSpeed: 150, turnRate: 2.8)
    private var carNode = SKNode()
    private var carTarget = 2   // carLoop[2] = (600,-400): head up the right side

    private var lastUpdate: TimeInterval = 0
    private var inputActive = false

    // MARK: - Setup

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.46, green: 0.73, blue: 0.42, alpha: 1) // grass
        addChild(worldNode)
        buildRoads()
        buildTrees()
        buildBuildings()

        busNode = makeBus()
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
            // sidewalk / curb (widest, light) under everything
            worldNode.addChild(roadLine(s.a, s.b, width: CGFloat(s.width) * scale + 40,
                                        color: SKColor(red: 0.82, green: 0.80, blue: 0.74, alpha: 1), z: -0.2))
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

    /// Faked height: draw a tall **front face** (the building body) with rows of
    /// windows, then cap it with a lighter **roof** offset up by the height. The
    /// face stays visible below the roof, so the block reads as having height —
    /// the GTA-style "perspective" — while the logic underneath is flat top-down.
    private func buildBuildings() {
        let palettes: [(wall: SKColor, roof: SKColor, win: SKColor)] = [
            (SKColor(red: 0.74, green: 0.52, blue: 0.46, alpha: 1),
             SKColor(red: 0.88, green: 0.68, blue: 0.60, alpha: 1),
             SKColor(red: 0.97, green: 0.93, blue: 0.70, alpha: 1)),
            (SKColor(red: 0.52, green: 0.60, blue: 0.72, alpha: 1),
             SKColor(red: 0.70, green: 0.78, blue: 0.88, alpha: 1),
             SKColor(red: 0.98, green: 0.96, blue: 0.76, alpha: 1)),
            (SKColor(red: 0.70, green: 0.66, blue: 0.56, alpha: 1),
             SKColor(red: 0.87, green: 0.83, blue: 0.74, alpha: 1),
             SKColor(red: 0.58, green: 0.80, blue: 0.95, alpha: 1)),
        ]
        for (i, b) in buildings.enumerated() {
            let pal = palettes[i % palettes.count]
            let node = SKNode()
            node.position = pt(b.center)
            node.zPosition = 5
            let w = b.size.width * scale, d = b.size.height * scale
            let h = b.height

            // soft shadow under the whole silhouette
            let shadow = SKShapeNode(rectOf: CGSize(width: w, height: d + h), cornerRadius: 8)
            shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
            shadow.position = CGPoint(x: 14, y: h / 2 - 14)
            node.addChild(shadow)

            // body = front face + bulk (spans footprint up to the roof)
            let body = SKShapeNode(rectOf: CGSize(width: w, height: d + h), cornerRadius: 6)
            body.fillColor = pal.wall
            body.strokeColor = SKColor(white: 0, alpha: 0.22); body.lineWidth = 2
            body.position = CGPoint(x: 0, y: h / 2)
            node.addChild(body)

            // windows across the exposed front face (the lower `h` band)
            let cols = max(2, Int(w / 90))
            let rows = max(1, Int(h / 60))
            for cx in 0..<cols {
                for ry in 0..<rows {
                    let win = SKShapeNode(rectOf: CGSize(width: w / CGFloat(cols) * 0.5,
                                                         height: h / CGFloat(rows) * 0.5),
                                         cornerRadius: 2)
                    win.fillColor = pal.win; win.strokeColor = .clear
                    win.position = CGPoint(x: -w / 2 + (CGFloat(cx) + 0.5) * (w / CGFloat(cols)),
                                           y: -d / 2 + (CGFloat(ry) + 0.5) * (h / CGFloat(rows)))
                    node.addChild(win)
                }
            }

            // roof cap on top
            let roof = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 6)
            roof.fillColor = pal.roof
            roof.strokeColor = SKColor(white: 0, alpha: 0.18); roof.lineWidth = 2
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)

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

    /// A proper top-down school bus: long yellow body, black trim stripes, a row
    /// of side windows, windshield + dark bumper at the front (+x).
    private func makeBus() -> SKNode {
        let node = SKNode()
        let length: CGFloat = 152, width: CGFloat = 58
        for sx in [-length * 0.30, length * 0.30] {
            for sy in [-width * 0.56, width * 0.56] {
                let wheel = SKShapeNode(rectOf: CGSize(width: length * 0.15, height: width * 0.14), cornerRadius: 3)
                wheel.fillColor = SKColor(white: 0.12, alpha: 1); wheel.strokeColor = .clear
                wheel.position = CGPoint(x: sx, y: sy); node.addChild(wheel)
            }
        }
        let body = SKShapeNode(rectOf: CGSize(width: length, height: width), cornerRadius: 12)
        body.fillColor = SKColor(red: 1.0, green: 0.80, blue: 0.16, alpha: 1)
        body.strokeColor = SKColor(red: 0.55, green: 0.40, blue: 0.05, alpha: 1); body.lineWidth = 2
        node.addChild(body)
        for sy in [-width * 0.34, width * 0.34] {
            let stripe = SKShapeNode(rectOf: CGSize(width: length * 0.86, height: width * 0.10), cornerRadius: 2)
            stripe.fillColor = SKColor(white: 0.12, alpha: 1); stripe.strokeColor = .clear
            stripe.position = CGPoint(x: -length * 0.04, y: sy); node.addChild(stripe)
        }
        let winCount = 5
        for i in 0..<winCount {
            let win = SKShapeNode(rectOf: CGSize(width: length * 0.12, height: width * 0.42), cornerRadius: 2)
            win.fillColor = SKColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1); win.strokeColor = .clear
            win.position = CGPoint(x: -length * 0.30 + CGFloat(i) * (length * 0.62 / CGFloat(winCount - 1)), y: 0)
            node.addChild(win)
        }
        let windshield = SKShapeNode(rectOf: CGSize(width: length * 0.09, height: width * 0.70), cornerRadius: 3)
        windshield.fillColor = SKColor(red: 0.70, green: 0.86, blue: 0.96, alpha: 1); windshield.strokeColor = .clear
        windshield.position = CGPoint(x: length * 0.40, y: 0); node.addChild(windshield)
        let bumper = SKShapeNode(rectOf: CGSize(width: length * 0.05, height: width * 0.92), cornerRadius: 2)
        bumper.fillColor = SKColor(white: 0.20, alpha: 1); bumper.strokeColor = .clear
        bumper.position = CGPoint(x: length * 0.49, y: 0); node.addChild(bumper)
        return node
    }

    /// Roadside trees — mostly ringing the map to fill the empty grass the follow
    /// camera shows at the edges, plus a few inside the blocks for life.
    private func buildTrees() {
        let spots: [Vec2] = [
            Vec2(-300, -560), Vec2(300, -560), Vec2(-300, 560), Vec2(300, 560),
            Vec2(-760, -150), Vec2(-760, 150), Vec2(760, -150), Vec2(760, 150),
            Vec2(-770, -560), Vec2(770, 560), Vec2(150, -290), Vec2(-150, 290),
        ]
        for s in spots { worldNode.addChild(tree(at: s)) }
    }

    private func tree(at v: Vec2) -> SKNode {
        let node = SKNode(); node.position = pt(v); node.zPosition = 6
        let r: CGFloat = 28
        let shadow = SKShapeNode(circleOfRadius: r * 1.05)
        shadow.fillColor = SKColor(white: 0, alpha: 0.15); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 8, y: -8); node.addChild(shadow)
        let trunk = SKShapeNode(rectOf: CGSize(width: 10, height: 16), cornerRadius: 2)
        trunk.fillColor = SKColor(red: 0.45, green: 0.30, blue: 0.18, alpha: 1); trunk.strokeColor = .clear
        trunk.position = CGPoint(x: 0, y: -r * 0.7); node.addChild(trunk)
        let canopy = SKShapeNode(circleOfRadius: r)
        canopy.fillColor = SKColor(red: 0.20, green: 0.52, blue: 0.26, alpha: 1)
        canopy.strokeColor = SKColor(red: 0.13, green: 0.38, blue: 0.18, alpha: 1); canopy.lineWidth = 2
        node.addChild(canopy)
        let hi = SKShapeNode(circleOfRadius: r * 0.55)
        hi.fillColor = SKColor(red: 0.28, green: 0.62, blue: 0.32, alpha: 1); hi.strokeColor = .clear
        hi.position = CGPoint(x: -r * 0.25, y: r * 0.25); node.addChild(hi)
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
        let target = busLoop[busTarget % busLoop.count]
        let dist = bus.position.distance(to: target)
        if dist < 70 { busTarget = (busTarget + 1) % busLoop.count }
        let throttle = dist < 180 ? 0.35 : 1.0
        applyMove(&bus, throttle: throttle, steer: bus.steer(toward: target), dt: dt)
    }

    private func driveCar(dt: Double) {
        let target = carLoop[carTarget % carLoop.count]
        let dist = car.position.distance(to: target)
        if dist < 70 { carTarget = (carTarget + 1) % carLoop.count }
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
        place(busNode, bus)
        place(carNode, car)
    }

    /// Position a vehicle node, nudged into its right-hand lane (in screen space,
    /// so opposing traffic sits on opposite sides of the road).
    private func place(_ node: SKNode, _ v: BusKinematics) {
        let phi = -CGFloat(v.heading)        // screen rotation (world z maps to -y)
        let base = pt(v.position)
        let off: CGFloat = 24                 // points into the right lane
        node.position = CGPoint(x: base.x + sin(phi) * off, y: base.y - cos(phi) * off)
        node.zRotation = phi
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
