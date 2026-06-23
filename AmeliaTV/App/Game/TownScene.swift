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
        Building(center: Vec2(-300, 200), size: CGSize(width: 160, height: 190), height: 110),
        Building(center: Vec2(300, 200), size: CGSize(width: 210, height: 160), height: 80),
    ]

    // A landmark building whose faked height re-projects from the camera each
    // frame, so it appears to change perspective (GTA-style) as the bus drives
    // around it. The logic underneath is still a flat top-down footprint.
    private let perspCenter = Vec2(300, -200)
    private let perspSize = CGSize(width: 200, height: 170)
    private let perspLean: CGFloat = 70
    private let perspNode = SKNode()
    private let perspWall = SKShapeNode()
    private let perspRoof = SKShapeNode()

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

    // Camera opens on a wide establishing shot of the whole town (so a CI capture
    // can verify scenery anywhere on the map), then eases in to follow the bus.
    private var elapsed: TimeInterval = 0
    private let wideZoom: CGFloat = 2.6
    private let closeZoom: CGFloat = 0.9
    private let establishHold: TimeInterval = 6.0
    private let establishEase: TimeInterval = 2.0

    // Pedestrians + "honk → the world reacts" (M2).
    private final class Ped {
        let node = SKNode()
        var pos: Vec2
        var target: Vec2
        let home: Vec2
        let reactorIndex: Int
        init(home: Vec2, reactorIndex: Int) {
            self.pos = home; self.target = home; self.home = home; self.reactorIndex = reactorIndex
        }
    }
    private var peds: [Ped] = []
    private let reactions = ReactionSystem()
    private var honkTimer: TimeInterval = 0
    private var honkCount = 0

    // Input: touch controls (iOS) write here; the scene also polls GameController.
    var controls: DriveControls?
    private let cruiseSpeed = 120.0
    private var honkButtonWasDown = false

    // A traffic light on the right road the bus (and car) stop at on red.
    private var light = TrafficLight(id: "main", position: Vec2(600, 0), phase: 0,
                                     green: 3, yellow: 1.5, red: 6)
    private var lampRed: SKShapeNode!
    private var lampYellow: SKShapeNode!
    private var lampGreen: SKShapeNode!

    // "Quick Stop!" challenge (CH-01): a ball crosses the right road; brake in time.
    private var quickStop = QuickStopChallenge()
    private var challengeDone = false
    private let challengePoint = Vec2(600, -150)
    private let ballNode = SKShapeNode(circleOfRadius: 13)
    private let meterBG = SKShapeNode()
    private let meterFill = SKShapeNode()
    private var challengeResumeAt: TimeInterval = -1   // demo waits at the stop until here

    // MARK: - Setup

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.46, green: 0.73, blue: 0.42, alpha: 1) // grass
        addChild(worldNode)
        buildRoads()
        buildTrees()
        buildBuildings()
        buildScenery()
        buildPeds()
        buildTrafficLight()
        buildPerspectiveBuilding()
        buildChallenge()

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
        cam.position = pt(Vec2(0, 0))   // start on the wide establishing shot
        cam.setScale(wideZoom)
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
        let shadow = SKShapeNode(rectOf: CGSize(width: length, height: width * 1.18), cornerRadius: 10)
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -5); node.addChild(shadow)
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
        let length: CGFloat = 150, width: CGFloat = 64
        let shadow = SKShapeNode(rectOf: CGSize(width: length, height: width * 1.16), cornerRadius: 26)
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -6); node.addChild(shadow)
        for sx in [-length * 0.30, length * 0.30] {
            for sy in [-width * 0.54, width * 0.54] {
                let wheel = SKShapeNode(rectOf: CGSize(width: length * 0.15, height: width * 0.13), cornerRadius: 4)
                wheel.fillColor = SKColor(white: 0.12, alpha: 1); wheel.strokeColor = .clear
                wheel.position = CGPoint(x: sx, y: sy); node.addChild(wheel)
            }
        }
        // rounder, friendlier body
        let body = SKShapeNode(rectOf: CGSize(width: length, height: width), cornerRadius: 28)
        body.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1)
        body.strokeColor = SKColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 1); body.lineWidth = 3
        node.addChild(body)
        // a couple of side windows toward the back
        for i in 0..<2 {
            let win = SKShapeNode(rectOf: CGSize(width: length * 0.13, height: width * 0.46), cornerRadius: 4)
            win.fillColor = SKColor(red: 0.66, green: 0.85, blue: 0.96, alpha: 1); win.strokeColor = .clear
            win.position = CGPoint(x: -length * 0.32 + CGFloat(i) * length * 0.17, y: 0); node.addChild(win)
        }
        // a cute face at the front (+x): big eyes looking ahead + rosy cheeks
        for sy in [-width * 0.22, width * 0.22] {
            let eyeWhite = SKShapeNode(circleOfRadius: width * 0.17)
            eyeWhite.fillColor = .white; eyeWhite.strokeColor = SKColor(white: 0, alpha: 0.12); eyeWhite.lineWidth = 1
            eyeWhite.position = CGPoint(x: length * 0.28, y: sy); node.addChild(eyeWhite)
            let pupil = SKShapeNode(circleOfRadius: width * 0.075)
            pupil.fillColor = .black; pupil.strokeColor = .clear
            pupil.position = CGPoint(x: length * 0.33, y: sy); node.addChild(pupil)
        }
        for sy in [-width * 0.36, width * 0.36] {
            let cheek = SKShapeNode(circleOfRadius: width * 0.085)
            cheek.fillColor = SKColor(red: 1.0, green: 0.56, blue: 0.56, alpha: 0.85); cheek.strokeColor = .clear
            cheek.position = CGPoint(x: length * 0.40, y: sy); node.addChild(cheek)
        }
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

    /// Cozy static dressing: a little park (pond + benches) in the open grass
    /// below the loop, a bus stop beside the road, and flower clusters scattered
    /// about. All off the roads so nothing blocks driving.
    private func buildScenery() {
        buildPark()
        addBusStop(at: Vec2(-160, -330))
        let flowers: [Vec2] = [
            Vec2(-500, -120), Vec2(500, 120), Vec2(120, -300), Vec2(-120, 300),
            Vec2(480, -300), Vec2(-690, 320), Vec2(690, -320),
        ]
        for f in flowers { addFlowers(at: f) }
    }

    /// A real city park below the loop: a soccer field with kids, a pond with a
    /// fountain statue + pigeons, benches, and shade trees.
    private func buildPark() {
        addSoccerField(center: Vec2(-330, 600), size: CGSize(width: 360, height: 210))
        addPond(at: Vec2(330, 600), size: CGSize(width: 250, height: 150))
        addStatue(at: Vec2(330, 600))                       // fountain statue in the pond
        addBench(at: Vec2(150, 600)); addBench(at: Vec2(520, 600))
        for p in [Vec2(120, 510), Vec2(540, 510), Vec2(-560, 710), Vec2(560, 710)] { addShadeTree(at: p) }
        for p in [Vec2(180, 650), Vec2(230, 560), Vec2(470, 660), Vec2(420, 560), Vec2(300, 700)] { addPigeon(at: p) }
        for p in [Vec2(-430, 560), Vec2(-250, 650), Vec2(-330, 540)] { addKid(at: p) }
    }

    private func addStatue(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 5
        let base = SKShapeNode(rectOf: CGSize(width: 46, height: 22), cornerRadius: 4)
        base.fillColor = SKColor(white: 0.72, alpha: 1)
        base.strokeColor = SKColor(white: 0, alpha: 0.2); base.lineWidth = 1
        node.addChild(base)
        let torso = SKShapeNode(rectOf: CGSize(width: 16, height: 26), cornerRadius: 6)
        torso.fillColor = SKColor(white: 0.80, alpha: 1); torso.strokeColor = .clear
        torso.position = CGPoint(x: 0, y: 16); node.addChild(torso)
        let head = SKShapeNode(circleOfRadius: 9)
        head.fillColor = SKColor(white: 0.82, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 34); node.addChild(head)
        worldNode.addChild(node)
    }

    private func addShadeTree(at v: Vec2) {
        let p = pt(v)
        let shade = SKShapeNode(ellipseOf: CGSize(width: 100, height: 66))
        shade.fillColor = SKColor(white: 0, alpha: 0.15); shade.strokeColor = .clear
        shade.position = CGPoint(x: p.x + 6, y: p.y - 14); shade.zPosition = 5
        worldNode.addChild(shade)
        let t = tree(at: v); t.zPosition = 6; worldNode.addChild(t)
    }

    private func addPigeon(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 7
        let body = SKShapeNode(ellipseOf: CGSize(width: 17, height: 11))
        body.fillColor = SKColor(white: 0.55, alpha: 1); body.strokeColor = .clear; node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 5)
        head.fillColor = SKColor(white: 0.64, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 8, y: 4); node.addChild(head)
        node.run(.repeatForever(.sequence([
            .rotate(toAngle: -0.4, duration: 0.45),
            .wait(forDuration: Double.random(in: 0.2...0.9)),
            .rotate(toAngle: 0, duration: 0.4),
            .wait(forDuration: Double.random(in: 0.3...1.1)),
        ])))
        worldNode.addChild(node)
    }

    private func addKid(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 8
        let shadow = SKShapeNode(circleOfRadius: 10)
        shadow.fillColor = SKColor(white: 0, alpha: 0.14); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 3, y: -4); node.addChild(shadow)
        let shirts: [SKColor] = [
            SKColor(red: 0.95, green: 0.45, blue: 0.50, alpha: 1),
            SKColor(red: 0.35, green: 0.70, blue: 0.85, alpha: 1),
            SKColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1),
        ]
        let body = SKShapeNode(circleOfRadius: 10)
        body.fillColor = shirts[Int.random(in: 0..<shirts.count)]
        body.strokeColor = SKColor(white: 0, alpha: 0.2); body.lineWidth = 1; node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 3); node.addChild(head)
        node.run(.repeatForever(.sequence([                 // jumping, playing
            .moveBy(x: 0, y: 12, duration: 0.24),
            .moveBy(x: 0, y: -12, duration: 0.22),
            .wait(forDuration: Double.random(in: 0.3...1.3)),
        ])))
        worldNode.addChild(node)
    }

    private func addSoccerField(center: Vec2, size: CGSize) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 4
        let w = size.width * scale, h = size.height * scale
        let field = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 6)
        field.fillColor = SKColor(red: 0.42, green: 0.70, blue: 0.42, alpha: 1)
        field.strokeColor = .white; field.lineWidth = 3
        node.addChild(field)
        let mid = SKShapeNode(rectOf: CGSize(width: 3, height: h))
        mid.fillColor = .white; mid.strokeColor = .clear; node.addChild(mid)
        let circle = SKShapeNode(circleOfRadius: h * 0.18)
        circle.strokeColor = .white; circle.lineWidth = 3; circle.fillColor = .clear; node.addChild(circle)
        for sx in [-w / 2, w / 2] {
            let goal = SKShapeNode(rectOf: CGSize(width: 12, height: h * 0.3), cornerRadius: 2)
            goal.strokeColor = .white; goal.lineWidth = 3
            goal.fillColor = SKColor(white: 1, alpha: 0.12)
            goal.position = CGPoint(x: sx, y: 0); node.addChild(goal)
        }
        let ball = SKShapeNode(circleOfRadius: 8)
        ball.fillColor = .white; ball.strokeColor = SKColor(white: 0, alpha: 0.4); ball.lineWidth = 1
        ball.position = CGPoint(x: w * 0.16, y: -h * 0.12); node.addChild(ball)
        worldNode.addChild(node)
    }

    private func addPond(at v: Vec2, size: CGSize) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 3
        let w = size.width * scale, h = size.height * scale
        let water = SKShapeNode(ellipseOf: CGSize(width: w, height: h))
        water.fillColor = SKColor(red: 0.35, green: 0.62, blue: 0.85, alpha: 1)
        water.strokeColor = SKColor(red: 0.58, green: 0.76, blue: 0.52, alpha: 1); water.lineWidth = 7
        node.addChild(water)
        let hi = SKShapeNode(ellipseOf: CGSize(width: w * 0.5, height: h * 0.4))
        hi.fillColor = SKColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 0.7); hi.strokeColor = .clear
        hi.position = CGPoint(x: -w * 0.12, y: h * 0.12); node.addChild(hi)
        worldNode.addChild(node)
    }

    private func addBench(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 4
        let seat = SKShapeNode(rectOf: CGSize(width: 46, height: 18), cornerRadius: 3)
        seat.fillColor = SKColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        seat.strokeColor = SKColor(white: 0, alpha: 0.2); seat.lineWidth = 1
        node.addChild(seat)
        worldNode.addChild(node)
    }

    private func addBusStop(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 6
        let roof = SKShapeNode(rectOf: CGSize(width: 72, height: 40), cornerRadius: 5)
        roof.fillColor = SKColor(red: 0.30, green: 0.55, blue: 0.66, alpha: 1)
        roof.strokeColor = SKColor(white: 0, alpha: 0.2); roof.lineWidth = 1
        node.addChild(roof)
        let post = SKShapeNode(rectOf: CGSize(width: 6, height: 30), cornerRadius: 2)
        post.fillColor = SKColor(white: 0.55, alpha: 1); post.strokeColor = .clear
        post.position = CGPoint(x: 48, y: -6); node.addChild(post)
        let sign = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 5)
        sign.fillColor = SKColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1)
        sign.strokeColor = .white; sign.lineWidth = 2
        sign.position = CGPoint(x: 48, y: 16); node.addChild(sign)
        worldNode.addChild(node)
    }

    private func addFlowers(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 4
        let colors = [
            SKColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1),
            SKColor(red: 0.98, green: 0.85, blue: 0.30, alpha: 1),
            SKColor(red: 0.70, green: 0.55, blue: 0.90, alpha: 1),
            SKColor.white,
        ]
        for i in 0..<5 {
            let dot = SKShapeNode(circleOfRadius: 7)
            dot.fillColor = colors[i % colors.count]; dot.strokeColor = .clear
            dot.position = CGPoint(x: CGFloat.random(in: -22...22), y: CGFloat.random(in: -22...22))
            node.addChild(dot)
        }
        worldNode.addChild(node)
    }

    // MARK: - Pedestrians & honk reactions

    private func buildPeds() {
        // Onlookers ringing the loop + clustered at the park and bus stop, so the
        // bus is always near a few and honk reactions land on camera.
        let homes: [Vec2] = [
            Vec2(-300, -340), Vec2(300, -340), Vec2(-300, 340), Vec2(300, 340),
            Vec2(-540, -150), Vec2(-540, 150), Vec2(540, -150), Vec2(540, 150),
            Vec2(80, 560), Vec2(-80, 560), Vec2(-160, -300),
        ]
        let shirts: [SKColor] = [
            SKColor(red: 0.90, green: 0.35, blue: 0.40, alpha: 1),
            SKColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1),
            SKColor(red: 0.40, green: 0.70, blue: 0.45, alpha: 1),
            SKColor(red: 0.95, green: 0.60, blue: 0.25, alpha: 1),
            SKColor(red: 0.62, green: 0.45, blue: 0.80, alpha: 1),
        ]
        for (i, h) in homes.enumerated() {
            let ped = Ped(home: h, reactorIndex: i)
            addPerson(to: ped.node, shirt: shirts[i % shirts.count])
            ped.node.position = pt(h)
            ped.node.zPosition = 8
            worldNode.addChild(ped.node)
            peds.append(ped)
        }
    }

    private func addPerson(to node: SKNode, shirt: SKColor) {
        let shadow = SKShapeNode(circleOfRadius: 14)
        shadow.fillColor = SKColor(white: 0, alpha: 0.15); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 4, y: -6); node.addChild(shadow)
        let body = SKShapeNode(circleOfRadius: 14)
        body.fillColor = shirt; body.strokeColor = SKColor(white: 0, alpha: 0.2); body.lineWidth = 1
        node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 4); node.addChild(head)
    }

    private func updatePeds(dt: Double) {
        for ped in peds {
            let to = ped.target - ped.pos
            let d = to.length
            if d < 6 {
                ped.target = offRoadTarget(near: ped.home)
            } else {
                ped.pos = ped.pos + to * min(1.0, (40 * dt) / d)
                ped.node.position = pt(ped.pos)
            }
        }
    }

    /// A wander target near `home` that is NOT on a road — so pedestrians amble on
    /// the grass/sidewalk and the bus never appears to drive through them.
    private func offRoadTarget(near home: Vec2) -> Vec2 {
        for _ in 0..<8 {
            let c = home + Vec2(Double.random(in: -70...70), Double.random(in: -70...70))
            if !net.isOnRoad(c) { return c }
        }
        return home
    }

    private func honk() {
        honkCount += 1
        busNode.run(.sequence([.scale(to: 1.12, duration: 0.08), .scale(to: 1.0, duration: 0.16)]))
        let ring = SKShapeNode(circleOfRadius: 24)
        ring.strokeColor = SKColor(white: 1, alpha: 0.85); ring.lineWidth = 5; ring.fillColor = .clear
        ring.position = busNode.position; ring.zPosition = 15
        worldNode.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 6, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        for ped in peds where reactions.reacts(atDistance: ped.pos.distance(to: bus.position)) {
            playReaction(ped)
        }
    }

    private func playReaction(_ ped: Ped) {
        switch reactions.reaction(forReactor: ped.reactorIndex, honkCount: honkCount) {
        case .hop:
            ped.node.run(.sequence([.moveBy(x: 0, y: 20, duration: 0.14), .moveBy(x: 0, y: -20, duration: 0.16)]))
        case .wave:
            ped.node.run(.sequence([.rotate(toAngle: 0.35, duration: 0.1),
                                    .rotate(toAngle: -0.35, duration: 0.2),
                                    .rotate(toAngle: 0, duration: 0.1)]))
        case .spin:
            ped.node.run(.rotate(byAngle: .pi * 2, duration: 0.5))
        case .cheer:
            ped.node.run(.sequence([.scale(to: 1.3, duration: 0.12), .scale(to: 1.0, duration: 0.18)]))
            spawnHeart(at: ped.node.position)
        case .heart:
            spawnHeart(at: ped.node.position)
        }
    }

    private func spawnHeart(at p: CGPoint) {
        let heart = heartNode()
        heart.position = CGPoint(x: p.x, y: p.y + 18); heart.zPosition = 20; heart.setScale(0.1)
        worldNode.addChild(heart)
        heart.run(.sequence([
            .group([.scale(to: 1.0, duration: 0.2),
                    .moveBy(x: 0, y: 70, duration: 1.2),
                    .sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.5)])]),
            .removeFromParent(),
        ]))
    }

    private func heartNode() -> SKNode {
        let n = SKNode()
        let pink = SKColor(red: 0.95, green: 0.40, blue: 0.55, alpha: 1)
        for dx in [-6.0, 6.0] {
            let c = SKShapeNode(circleOfRadius: 8)
            c.fillColor = pink; c.strokeColor = .clear
            c.position = CGPoint(x: CGFloat(dx), y: 4); n.addChild(c)
        }
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: -13, y: 5)); tri.addLine(to: CGPoint(x: 13, y: 5))
        tri.addLine(to: CGPoint(x: 0, y: -14)); tri.closeSubpath()
        let t = SKShapeNode(path: tri); t.fillColor = pink; t.strokeColor = .clear; n.addChild(t)
        return n
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime
        guard dt > 0 else { return }

        elapsed += dt
        light.update(dt: dt)
        updateChallenge(dt: dt)
        driveBus(dt: dt)
        driveCar(dt: dt)
        updatePeds(dt: dt)
        // The demo bus honks on its own so CI captures reactions; a real driver
        // honks with the button instead.
        if !inputActive {
            honkTimer += dt
            if honkTimer >= 3.0 { honkTimer = 0; honk() }
        }
        updateLightRender()
        syncNodes()
        updateCamera()
        updatePerspectiveBuilding()
    }

    /// Hold the wide establishing shot, then smoothly ease in to follow the bus.
    private func updateCamera() {
        let center = pt(Vec2(0, 0))
        if elapsed < establishHold {
            cam.position = center
            cam.setScale(wideZoom)
            return
        }
        let t = min(1.0, (elapsed - establishHold) / establishEase)
        let e = CGFloat(t * t * (3 - 2 * t))   // smoothstep
        cam.setScale(wideZoom + (closeZoom - wideZoom) * e)
        let bp = busNode.position
        cam.position = CGPoint(x: center.x + (bp.x - center.x) * e,
                               y: center.y + (bp.y - center.y) * e)
    }

    private func driveBus(dt: Double) {
        // Gather input from touch (iOS) and/or a controller / Siri Remote. The
        // bus auto-rolls forward; the player only steers, brakes, and honks.
        var steer = 0.0
        var braking = false
        var active = false

        if let c = controls {
            if c.consumeHonk() { honk() }
            if c.steer != 0 { steer = c.steer; active = true }
            if c.braking { braking = true; active = true }
            if c.engaged { active = true }
        }
        if let g = controllerDrive() {
            if abs(g.steer) > 0.12 { steer = g.steer }
            if g.braking { braking = true }
            if g.honk { honk() }
            if g.active { active = true }
        }
        if active { inputActive = true }

        if inputActive {
            var throttle: Double
            if braking { throttle = -0.8 }
            else if bus.speed > cruiseSpeed { throttle = 0.0 }   // coast at cruise
            else { throttle = 0.8 }
            if shouldStop(bus.position) { throttle = -1.0 }
            applyMove(&bus, throttle: throttle, steer: steer, dt: dt)
            return
        }

        // Demo attract-drive: follow the loop, easing off into corners.
        let target = busLoop[busTarget % busLoop.count]
        let dist = bus.position.distance(to: target)
        if dist < 70 { busTarget = (busTarget + 1) % busLoop.count }
        var throttle = dist < 180 ? 0.35 : 1.0
        if shouldStop(bus.position) { throttle = -1.0 }
        if quickStop.state == .running { throttle = -0.5 }   // demo brakes (gently) for the ball
        if challengeDone, elapsed < challengeResumeAt { throttle = -1.0 }   // dwell at the stop
        applyMove(&bus, throttle: throttle, steer: bus.steer(toward: target), dt: dt)
    }

    private func driveCar(dt: Double) {
        let target = carLoop[carTarget % carLoop.count]
        let dist = car.position.distance(to: target)
        if dist < 70 { carTarget = (carTarget + 1) % carLoop.count }
        var throttle = dist < 180 ? 0.4 : 1.0
        if shouldStop(car.position) { throttle = -1.0 }
        applyMove(&car, throttle: throttle, steer: car.steer(toward: target), dt: dt)
    }

    /// True when a vehicle should hold at the red light's stop zone.
    private func shouldStop(_ pos: Vec2) -> Bool {
        light.state == .red && pos.distance(to: light.position) < 95
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
        if abs(p.x - perspCenter.x) < Double(perspSize.width / 2),
           abs(p.z - perspCenter.z) < Double(perspSize.height / 2) {
            return true
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

    /// Steer / brake / honk from an MFi controller or the Siri Remote. Honk is
    /// edge-detected so one press = one honk. Steer left/right; brake = B / left
    /// trigger (controller) or swipe-down (remote); honk = A or Play/Pause.
    private func controllerDrive() -> (steer: Double, braking: Bool, honk: Bool, active: Bool)? {
        #if canImport(GameController)
        for c in GCController.controllers() {
            if let g = c.extendedGamepad {
                let stick = g.leftThumbstick.xAxis.value
                let steer = Double(abs(stick) > 0.12 ? stick : g.dpad.xAxis.value)
                let braking = g.buttonB.isPressed || g.leftTrigger.value > 0.3
                let honkDown = g.buttonA.isPressed || g.buttonX.isPressed
                let honk = honkDown && !honkButtonWasDown
                honkButtonWasDown = honkDown
                return (steer, braking, honk, abs(steer) > 0.12 || braking || honkDown)
            } else if let m = c.microGamepad {
                m.reportsAbsoluteDpadValues = true
                let steer = Double(m.dpad.xAxis.value)
                let braking = m.dpad.yAxis.value < -0.5
                let honkDown = m.buttonA.isPressed || m.buttonX.isPressed
                let honk = honkDown && !honkButtonWasDown
                honkButtonWasDown = honkDown
                return (steer, braking, honk, abs(steer) > 0.12 || braking || honkDown)
            }
        }
        #endif
        return nil
    }

    // MARK: - Traffic light

    private func buildTrafficLight() {
        let node = SKNode()
        node.position = pt(Vec2(680, 70))   // roadside, NE corner of the junction
        node.zPosition = 7
        let housing = SKShapeNode(rectOf: CGSize(width: 34, height: 90), cornerRadius: 8)
        housing.fillColor = SKColor(white: 0.16, alpha: 1)
        housing.strokeColor = SKColor(white: 0, alpha: 0.25); housing.lineWidth = 2
        node.addChild(housing)
        func lamp(_ y: CGFloat, _ color: SKColor) -> SKShapeNode {
            let l = SKShapeNode(circleOfRadius: 11)
            l.fillColor = color; l.strokeColor = .clear; l.position = CGPoint(x: 0, y: y)
            node.addChild(l); return l
        }
        lampRed = lamp(28, SKColor(red: 0.92, green: 0.24, blue: 0.22, alpha: 1))
        lampYellow = lamp(0, SKColor(red: 0.96, green: 0.80, blue: 0.24, alpha: 1))
        lampGreen = lamp(-28, SKColor(red: 0.30, green: 0.80, blue: 0.36, alpha: 1))
        worldNode.addChild(node)
        updateLightRender()
    }

    private func updateLightRender() {
        lampRed.alpha = light.state == .red ? 1.0 : 0.16
        lampYellow.alpha = light.state == .yellow ? 1.0 : 0.16
        lampGreen.alpha = light.state == .green ? 1.0 : 0.16
    }

    // MARK: - Perspective landmark building

    private func buildPerspectiveBuilding() {
        perspNode.position = pt(perspCenter)
        perspNode.zPosition = 5
        let w = perspSize.width * scale, d = perspSize.height * scale
        let foot = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 4)
        foot.fillColor = SKColor(red: 0.52, green: 0.55, blue: 0.64, alpha: 1)
        foot.strokeColor = SKColor(white: 0, alpha: 0.25); foot.lineWidth = 2
        perspNode.addChild(foot)
        perspWall.fillColor = SKColor(red: 0.60, green: 0.63, blue: 0.72, alpha: 1)
        perspWall.strokeColor = SKColor(white: 0, alpha: 0.18); perspWall.lineWidth = 1
        perspNode.addChild(perspWall)
        perspRoof.fillColor = SKColor(red: 0.80, green: 0.83, blue: 0.90, alpha: 1)
        perspRoof.strokeColor = SKColor(white: 0, alpha: 0.2); perspRoof.lineWidth = 2
        perspNode.addChild(perspRoof)
        worldNode.addChild(perspNode)
        updatePerspectiveBuilding()
    }

    /// Re-project the box from the camera each frame: the roof leans in the
    /// direction away from the camera, revealing the near walls — so the building
    /// looks like it turns as the bus circles it.
    private func updatePerspectiveBuilding() {
        let foot = pt(perspCenter)
        var dx = foot.x - cam.position.x, dy = foot.y - cam.position.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len > 1 { dx /= len; dy /= len } else { dx = 0; dy = 1 }
        let off = CGPoint(x: dx * perspLean, y: dy * perspLean)
        let hw = perspSize.width * scale / 2, hh = perspSize.height * scale / 2
        let f = [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh),
                 CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)]
        let r = f.map { CGPoint(x: $0.x + off.x, y: $0.y + off.y) }
        let body = CGMutablePath()
        for i in 0..<4 {
            let j = (i + 1) % 4
            body.move(to: f[i]); body.addLine(to: f[j])
            body.addLine(to: r[j]); body.addLine(to: r[i]); body.closeSubpath()
        }
        perspWall.path = body
        let roof = CGMutablePath()
        roof.addRoundedRect(in: CGRect(x: -hw + off.x, y: -hh + off.y, width: hw * 2, height: hh * 2),
                            cornerWidth: 4, cornerHeight: 4)
        perspRoof.path = roof
    }

    // MARK: - Quick-stop pose (placeholder for the CH-01 challenge)

    // MARK: - "Quick Stop!" challenge (CH-01)

    private func buildChallenge() {
        // a kid at the west curb of the right road, about to chase the ball
        let kid = SKNode(); kid.position = pt(Vec2(515, -150)); kid.zPosition = 8
        let sh = SKShapeNode(circleOfRadius: 10)
        sh.fillColor = SKColor(white: 0, alpha: 0.14); sh.strokeColor = .clear
        sh.position = CGPoint(x: 3, y: -4); kid.addChild(sh)
        let body = SKShapeNode(circleOfRadius: 11)
        body.fillColor = SKColor(red: 0.95, green: 0.5, blue: 0.3, alpha: 1)
        body.strokeColor = SKColor(white: 0, alpha: 0.2); body.lineWidth = 1; kid.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 4, y: 4); kid.addChild(head)
        worldNode.addChild(kid)

        // the ball, resting by the curb until the challenge arms
        ballNode.fillColor = .white; ballNode.strokeColor = SKColor(white: 0, alpha: 0.4); ballNode.lineWidth = 2
        ballNode.position = pt(Vec2(548, -150)); ballNode.zPosition = 9
        for a in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 2.5) {
            let spot = SKShapeNode(circleOfRadius: 3)
            spot.fillColor = SKColor(white: 0.1, alpha: 0.8); spot.strokeColor = .clear
            spot.position = CGPoint(x: CGFloat(cos(a) * 5), y: CGFloat(sin(a) * 5)); ballNode.addChild(spot)
        }
        worldNode.addChild(ballNode)

        // the reaction meter, floating above the bus while the challenge runs
        meterBG.path = CGPath(roundedRect: CGRect(x: -60, y: -9, width: 120, height: 18),
                              cornerWidth: 9, cornerHeight: 9, transform: nil)
        meterBG.fillColor = SKColor(white: 0, alpha: 0.45)
        meterBG.strokeColor = SKColor(white: 1, alpha: 0.55); meterBG.lineWidth = 2
        meterBG.zPosition = 25; meterBG.isHidden = true; worldNode.addChild(meterBG)
        meterFill.strokeColor = .clear; meterFill.zPosition = 26; meterFill.isHidden = true
        worldNode.addChild(meterFill)
    }

    private func updateChallenge(dt: Double) {
        if quickStop.state == .idle, !challengeDone {
            let b = bus.position
            if abs(b.x - challengePoint.x) < 120, b.z > -320, b.z < challengePoint.z {
                quickStop.arm()
                startBallRoll()
                meterBG.isHidden = false; meterFill.isHidden = false
            }
        }
        guard quickStop.state == .running else { return }
        quickStop.update(dt: dt, busSpeed: bus.speed)
        layoutMeter()
        if quickStop.state == .success { onChallengeSuccess() }
        else if quickStop.state == .missed { onChallengeMissed() }
    }

    private func startBallRoll() {
        ballNode.removeAllActions()
        ballNode.position = pt(Vec2(548, -150))
        ballNode.run(.group([
            .move(to: pt(Vec2(664, -150)), duration: quickStop.duration + 0.6),
            .repeatForever(.rotate(byAngle: .pi * 2, duration: 0.5)),
        ]))
    }

    private func layoutMeter() {
        let p = busNode.position
        meterBG.position = CGPoint(x: p.x, y: p.y + 72)
        let m = CGFloat(quickStop.meter)
        meterFill.path = CGPath(roundedRect: CGRect(x: -58, y: -7, width: max(0.1, 116 * m), height: 14),
                                cornerWidth: 7, cornerHeight: 7, transform: nil)
        meterFill.position = CGPoint(x: p.x, y: p.y + 72)
        meterFill.fillColor = SKColor(red: 0.92 - 0.55 * m, green: 0.30 + 0.55 * m, blue: 0.32, alpha: 1)
    }

    private func onChallengeSuccess() {
        challengeDone = true
        challengeResumeAt = elapsed + 4.0          // wait for the kid (and let CI catch it)
        meterBG.isHidden = true; meterFill.isHidden = true
        sparkleBurst(at: busNode.position)
        showScore(quickStop.score, at: busNode.position)
    }

    private func onChallengeMissed() {
        // No harsh failure: tuck the meter away and let it re-arm on a later pass.
        meterBG.isHidden = true; meterFill.isHidden = true
        quickStop.reset()
    }

    private func sparkleBurst(at p: CGPoint) {
        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1),
            SKColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1),
            .white,
        ]
        for _ in 0..<12 {
            let s = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6))
            s.fillColor = colors[Int.random(in: 0..<colors.count)]; s.strokeColor = .clear
            s.position = p; s.zPosition = 24; worldNode.addChild(s)
            let ang = CGFloat.random(in: 0...(.pi * 2)), dist = CGFloat.random(in: 40...95)
            s.run(.sequence([
                .group([.move(by: CGVector(dx: cos(ang) * dist, dy: sin(ang) * dist), duration: 0.6),
                        .fadeOut(withDuration: 0.6)]),
                .removeFromParent(),
            ]))
        }
    }

    private func showScore(_ score: Int, at p: CGPoint) {
        let label = SKLabelNode(text: "+\(score)")
        label.fontName = "AvenirNext-Bold"; label.fontSize = 42
        label.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        label.position = CGPoint(x: p.x, y: p.y + 44); label.zPosition = 27
        worldNode.addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 50, duration: 3.2),
                    .sequence([.wait(forDuration: 2.8), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent(),
        ]))
    }
}
