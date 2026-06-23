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
final class TownScene: SKScene, EpisodeWorld {

    // World→screen: 1 world unit = `scale` points. The camera follows the bus,
    // so the town is bigger than the screen (you see a moving window of it).
    private let scale: CGFloat = 2.0

    private let net = RoadNetwork.welles
    private let cam = SKCameraNode()
    private let worldNode = SKNode()

    // Surrounding buildings (outside the park roads): apartments on Western (west),
    // restaurants/shops on Sunnyside (south). Church + library + school get their
    // own builders below.
    private struct Building { var center: Vec2; var size: CGSize; var height: CGFloat }
    private let buildings: [Building] = [
        Building(center: Vec2(-1010, -320), size: CGSize(width: 220, height: 300), height: 150),  // apartments W
        Building(center: Vec2(-1010, 160), size: CGSize(width: 220, height: 280), height: 120),   // apartments W
        Building(center: Vec2(160, 920), size: CGSize(width: 240, height: 190), height: 90),       // restaurant S
        Building(center: Vec2(560, 940), size: CGSize(width: 220, height: 180), height: 80),       // shop S
        Building(center: Vec2(-200, 920), size: CGSize(width: 280, height: 210), height: 100),     // the school (S, off Sunnyside)
    ]

    // A landmark building whose faked height re-projects from the camera each
    // frame, so it appears to change perspective (GTA-style) as the bus drives
    // around it. The logic underneath is still a flat top-down footprint.
    // The library, across Lincoln Ave on the east.
    private let perspCenter = Vec2(1020, 300)
    private let perspSize = CGSize(width: 230, height: 200)
    private let perspLean: CGFloat = 70
    private let perspNode = SKNode()
    private let perspWall = SKShapeNode()
    private let perspRoof = SKShapeNode()

    // The bus drives the loop clockwise; the car drives it the other way, so the
    // two pass on opposite sides (real two-way traffic) instead of tailgating.
    private let busLoop = RoadNetwork.wellesLoop
    private let carLoop = Array(RoadNetwork.wellesLoop.reversed())

    private var bus = BusKinematics(position: Vec2(-300, -700), heading: 0,
                                    maxSpeed: 170, turnRate: 2.8)
    private var busNode = SKNode()
    private var busTarget = 1   // first head along Montrose toward the NE corner

    private var car = BusKinematics(position: Vec2(200, 700), heading: 0,
                                    maxSpeed: 150, turnRate: 2.8)
    private var carNode = SKNode()
    private var carTarget = 1   // carLoop[1] = (820,700): head east along Sunnyside

    private var lastUpdate: TimeInterval = 0
    private var inputActive = false

    // Camera opens on a wide establishing shot of the whole town (so a CI capture
    // can verify scenery anywhere on the map), then eases in to follow the bus.
    private var elapsed: TimeInterval = 0
    private let wideZoom: CGFloat = 3.0    // bigger Welles map needs a wider establishing shot
    private let closeZoom: CGFloat = 1.0
    // A brief wide shot of the town, then ease in to follow the bus as the ride
    // begins. Kept short so the whole first ride fits a CI capture window.
    private let establishHold: TimeInterval = 4.0
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

    // MARK: - Adventure (M3): the "first ride" episode runs on the road network.
    // The bus drives to the bus stop, picks up Pip, takes her to the school, and
    // earns a reward — drive → stop → pick up → drop off → reward — sequenced by
    // the pure, unit-tested `EpisodeRunner` (this scene is its `EpisodeWorld`).
    var hud: AdventureHUD?
    private var localizer = Localizer(table: [:])
    private var dialogue: DialogueDirector!
    private let speaker = SpeechSpeaker()
    private var runner: EpisodeRunner?
    private let townMap = TownMap.demo
    private var language: Language = .en
    private var episodeStarted = false
    private var hasGoal = false                    // true once the ride gives a first target
    private var episodeTarget: EpisodeTarget?      // current drive goal (braking + beacon)
    private var awardedStars = 0
    private var subtitleClearAt: TimeInterval = -1
    private var pipNode = SKNode()                 // Pip waiting at the stop
    private let schoolPlace = Vec2(-200, 700)      // drop-off, on Sunnyside (south)
    private let schoolDoor = Vec2(-200, 830)       // the school building sits south of the road
    private let beaconNode = SKShapeNode()         // floating arrow to the goal

    // A traffic light on Sunnyside (south road) the bus (and car) stop at on red.
    private var light = TrafficLight(id: "main", position: Vec2(300, 700), phase: 0,
                                     green: 3, yellow: 1.5, red: 6)
    private var lampRed: SKShapeNode!
    private var lampYellow: SKShapeNode!
    private var lampGreen: SKShapeNode!

    // "Quick Stop!" challenge (CH-01): a ball crosses the right road; brake in time.
    private var quickStop = QuickStopChallenge()
    private var challengeDone = false
    private let challengePoint = Vec2(100, -700)   // on Montrose (north road)
    private let ballNode = SKShapeNode(circleOfRadius: 13)
    private let meterBG = SKShapeNode()
    private let meterFill = SKShapeNode()
    private let brakeCue = SKNode()                    // pulsing "Brake!" prompt above the meter
    private let brakeCueLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let kidChaser = SKNode()                   // the kid who chases the ball
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
        loadContent()
        buildSchoolSign()
        buildPassenger()
        buildBeacon()

        busNode = makeBus()
        busNode.zPosition = 10
        worldNode.addChild(busNode)

        carNode = makeKenneyCar("car_red_1")
        carNode.zPosition = 10
        worldNode.addChild(carNode)

        addChild(cam)
        camera = cam
        cam.position = pt(Vec2(10, 0))   // start on the wide establishing shot
        cam.setScale(wideZoom)
        syncNodes()
    }

    private func pt(_ v: Vec2) -> CGPoint { CGPoint(x: CGFloat(v.x) * scale, y: -CGFloat(v.z) * scale) }

    // MARK: - World build

    private func buildRoads() {
        // Intersection pads first (under the strips) so corners read as squares of
        // asphalt where two streets cross, not rounded line-caps.
        for c in net.intersections() { addIntersectionPad(at: c, width: 110) }

        for s in net.segments {
            // sidewalk / curb (widest, light) under everything
            worldNode.addChild(roadLine(s.a, s.b, width: CGFloat(s.width) * scale + 40,
                                        color: SKColor(red: 0.82, green: 0.80, blue: 0.74, alpha: 1), z: -0.2))
            // casing (slightly wider, darker) then the road surface
            worldNode.addChild(roadLine(s.a, s.b, width: CGFloat(s.width) * scale + 8,
                                        color: SKColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1), z: 0))
            worldNode.addChild(roadLine(s.a, s.b, width: CGFloat(s.width) * scale,
                                        color: SKColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1), z: 0.1))
            // solid white edge lines just inside both curbs, then the dashed center.
            addEdgeLines(s.a, s.b, halfWidth: s.width / 2 - 7)
            worldNode.addChild(centerDashes(s.a, s.b))
        }

        // Painted zebra crosswalks where children cross: at the bus stop, the
        // school drop-off, and the traffic light. Bars run across the road.
        addCrosswalk(at: Vec2(-200, -700), along: Vec2(1, 0), roadWidth: 110)   // bus stop (Montrose)
        addCrosswalk(at: Vec2(-200, 700), along: Vec2(1, 0), roadWidth: 110)    // school (Sunnyside)
        addCrosswalk(at: Vec2(300, 700), along: Vec2(1, 0), roadWidth: 110)     // traffic light (Sunnyside)
    }

    /// A square of asphalt under a road junction, so crossing streets meet in a
    /// real intersection instead of two round line-caps overlapping.
    private func addIntersectionPad(at v: Vec2, width: CGFloat) {
        let pad = SKShapeNode(rectOf: CGSize(width: width * scale + 8, height: width * scale + 8), cornerRadius: 6)
        pad.position = pt(v)
        pad.fillColor = SKColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
        pad.strokeColor = SKColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1); pad.lineWidth = 8
        pad.zPosition = 0.15
        worldNode.addChild(pad)
    }

    /// Two solid white lane-edge lines, offset to either side of the centerline.
    private func addEdgeLines(_ a: Vec2, _ b: Vec2, halfWidth: Double) {
        let d = b - a
        let len = d.length
        guard len > 1e-6 else { return }
        let perp = Vec2(-d.z / len, d.x / len)   // unit normal in world space
        for side in [-1.0, 1.0] {
            let off = perp * (halfWidth * side)
            let line = roadLine(a + off, b + off, width: 2.5, color: SKColor(white: 0.95, alpha: 0.6), z: 0.9)
            line.lineCap = .butt
            worldNode.addChild(line)
        }
    }

    /// A zebra crosswalk centred on `at`: white bars laid across the road,
    /// perpendicular to the travel direction `along`.
    private func addCrosswalk(at center: Vec2, along dir: Vec2, roadWidth: Double) {
        let len = dir.length
        guard len > 1e-6 else { return }
        let travel = Vec2(dir.x / len, dir.z / len)
        let across = Vec2(-travel.z, travel.x)     // unit across the road, in world
        let bars = 6
        let span = 64.0                            // total length painted along travel
        for i in 0..<bars {
            let t = (Double(i) / Double(bars - 1) - 0.5) * span
            let mid = center + travel * t
            let line = roadLine(mid - across * (roadWidth / 2 - 8),
                                mid + across * (roadWidth / 2 - 8),
                                width: 7, color: SKColor(white: 0.95, alpha: 0.85), z: 0.95)
            line.lineCap = .butt
            worldNode.addChild(line)
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

    // Kenney art (CC0, Racing Pack) — see AmeliaTV/Assets/Kenney/. The hero bus
    // and the oblique buildings stay hand-drawn; traffic, people, and trees use
    // these sprites.
    private let kenneyCharacters = ["character_brown_blue", "character_blonde_red",
                                    "character_black_green", "character_blonde_white",
                                    "character_brown_red"]

    /// Load a bundled Kenney PNG as a sprite scaled to `height`, preserving aspect.
    private func kenneySprite(_ name: String, height: CGFloat) -> SKSpriteNode {
        let s = SKSpriteNode(imageNamed: name)
        if s.size.height > 1 {
            s.size = CGSize(width: height * (s.size.width / s.size.height), height: height)
        } else {
            s.size = CGSize(width: height, height: height)   // texture missing — visible fallback
        }
        return s
    }

    /// A Kenney top-down car. The art faces "up", so the sprite is turned to point
    /// along +x; the container is what the scene rotates to the heading.
    private func makeKenneyCar(_ name: String) -> SKNode {
        let node = SKNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 100, height: 54))
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -5); node.addChild(shadow)
        let car = kenneySprite(name, height: 96)
        car.zRotation = -.pi / 2
        node.addChild(car)
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
            Vec2(-460, -870), Vec2(330, -860),          // N, beyond Montrose (flanking the church)
            Vec2(-960, -350), Vec2(-960, 300),          // W, beyond Western
            Vec2(1010, -150), Vec2(1090, 480),          // E, beyond Lincoln
            Vec2(-520, 880), Vec2(420, 880),            // S, beyond Sunnyside
            Vec2(210, 240), Vec2(300, 330), Vec2(170, 380), Vec2(290, 200),  // adventure grove (inside)
        ]
        for s in spots { worldNode.addChild(tree(at: s)) }
    }

    private func tree(at v: Vec2) -> SKNode {
        let node = SKNode(); node.position = pt(v); node.zPosition = 6
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 58, height: 30))
        shadow.fillColor = SKColor(white: 0, alpha: 0.15); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 4, y: -22); node.addChild(shadow)
        node.addChild(kenneySprite("tree_large", height: 66))
        return node
    }

    /// Cozy static dressing: a little park (pond + benches) in the open grass
    /// below the loop, a bus stop beside the road, and flower clusters scattered
    /// about. All off the roads so nothing blocks driving.
    private func buildScenery() {
        buildPark()
        addChurch(at: Vec2(40, -900))      // across Montrose, on the north
        addBusStop(at: Vec2(-200, -600))   // on the Montrose curb, inside the park
        let flowers: [Vec2] = [
            Vec2(-500, -400), Vec2(-300, 250), Vec2(120, -300), Vec2(-150, 450),
            Vec2(380, -350), Vec2(-650, 0), Vec2(60, 520),
        ]
        for f in flowers { addFlowers(at: f) }
    }

    /// Welles Park's interior, laid out like the real place: a baseball diamond on
    /// the north, the gym + indoor-pool fieldhouse in the middle, tennis and
    /// pickleball courts, a playground, a pond with a fountain, and an adventure
    /// grove of trees full of children. Everything sits off the perimeter roads.
    private func buildPark() {
        addBaseballField(home: Vec2(-470, -250))                 // NW diamond
        addTennisCourts(center: Vec2(150, -360))                 // N, west of Lincoln
        addFieldhouse(center: Vec2(-300, 10))                    // gym + indoor pool
        addPond(at: Vec2(290, -40), size: CGSize(width: 220, height: 140))
        addStatue(at: Vec2(290, -40))                            // fountain statue in the pond
        addPlayground(center: Vec2(-430, 300))                   // SW
        addPickleball(center: Vec2(40, 320))                     // S-centre
        addBench(at: Vec2(150, -40)); addBench(at: Vec2(430, -40))
        for p in [Vec2(-640, -560), Vec2(-640, 560), Vec2(450, -560), Vec2(450, 540)] { addShadeTree(at: p) }
        for p in [Vec2(200, -10), Vec2(380, 0), Vec2(240, -120)] { addPigeon(at: p) }
        // adventure grove (SE interior): kids playing among the trees.
        for p in [Vec2(300, 240), Vec2(380, 300), Vec2(250, 320), Vec2(360, 200)] { addKid(at: p) }
    }

    /// A baseball diamond: a green outfield, a tan infield "pie", white base lines
    /// out to first/third, and little bases + a pitcher's mound.
    private func addBaseballField(home: Vec2) {
        let node = SKNode(); node.position = pt(home); node.zPosition = 4
        // outfield arc (a big rounded wedge of grass, mowed lighter than the park)
        let outfield = SKShapeNode(circleOfRadius: 175)
        outfield.fillColor = SKColor(red: 0.40, green: 0.68, blue: 0.40, alpha: 1)
        outfield.strokeColor = SKColor(white: 1, alpha: 0.25); outfield.lineWidth = 2
        outfield.position = CGPoint(x: 90, y: -90); node.addChild(outfield)
        // infield dirt: a diamond (rotated square) anchored at home plate.
        let infield = SKShapeNode(rectOf: CGSize(width: 150, height: 150), cornerRadius: 8)
        infield.fillColor = SKColor(red: 0.80, green: 0.62, blue: 0.42, alpha: 1)
        infield.strokeColor = .clear
        infield.zRotation = .pi / 4
        infield.position = CGPoint(x: 60, y: -60); node.addChild(infield)
        // base lines: home → first (along +x) and home → third (downward)
        for end in [CGPoint(x: 150, y: 0), CGPoint(x: 0, y: -150)] {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: .zero); path.addLine(to: end)
            line.path = path; line.strokeColor = SKColor(white: 1, alpha: 0.8); line.lineWidth = 3
            node.addChild(line)
        }
        for b in [CGPoint(x: 0, y: 0), CGPoint(x: 106, y: 0), CGPoint(x: 0, y: -106), CGPoint(x: 106, y: -106)] {
            let base = SKShapeNode(rectOf: CGSize(width: 12, height: 12), cornerRadius: 2)
            base.fillColor = .white; base.strokeColor = .clear; base.position = b; node.addChild(base)
        }
        let mound = SKShapeNode(circleOfRadius: 9)
        mound.fillColor = SKColor(red: 0.74, green: 0.56, blue: 0.38, alpha: 1); mound.strokeColor = .clear
        mound.position = CGPoint(x: 53, y: -53); node.addChild(mound)
        worldNode.addChild(node)
    }

    /// A pair of tennis/sport courts: colored hard-courts with a white boundary,
    /// service lines, and a net across the middle.
    private func addCourt(at center: Vec2, size: CGSize, surface: SKColor) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 4
        let w = size.width * scale, h = size.height * scale
        let court = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 4)
        court.fillColor = surface
        court.strokeColor = .white; court.lineWidth = 3; node.addChild(court)
        let net = SKShapeNode(rectOf: CGSize(width: w, height: 3))
        net.fillColor = SKColor(white: 1, alpha: 0.9); net.strokeColor = .clear; node.addChild(net)
        let service = SKShapeNode(rectOf: CGSize(width: w * 0.6, height: h * 0.5))
        service.strokeColor = SKColor(white: 1, alpha: 0.7); service.lineWidth = 2; service.fillColor = .clear
        node.addChild(service)
        worldNode.addChild(node)
    }

    private func addTennisCourts(center: Vec2) {
        let surface = SKColor(red: 0.30, green: 0.52, blue: 0.66, alpha: 1)   // blue hard-court
        addCourt(at: center + Vec2(0, -52), size: CGSize(width: 150, height: 78), surface: surface)
        addCourt(at: center + Vec2(0, 52), size: CGSize(width: 150, height: 78), surface: surface)
    }

    private func addPickleball(center: Vec2) {
        let surface = SKColor(red: 0.62, green: 0.40, blue: 0.34, alpha: 1)   // clay/green pickleball
        addCourt(at: center + Vec2(-78, 0), size: CGSize(width: 120, height: 64), surface: surface)
        addCourt(at: center + Vec2(78, 0), size: CGSize(width: 120, height: 64), surface: surface)
    }

    /// The Welles Park fieldhouse: one faked-height building that holds the
    /// gymnasium and the indoor pool. A flat top-down footprint with a tall face,
    /// big windows, and a small "POOL / GYM" door marker.
    private func addFieldhouse(center: Vec2) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 5
        let w = 260 * scale, d = 180 * scale, h: CGFloat = 90
        let shadow = SKShapeNode(rectOf: CGSize(width: w + 10, height: d + 10), cornerRadius: 8)
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 8, y: -10); node.addChild(shadow)
        let face = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 8)
        face.fillColor = SKColor(red: 0.72, green: 0.40, blue: 0.34, alpha: 1)   // brick
        face.strokeColor = SKColor(white: 0, alpha: 0.2); face.lineWidth = 1; node.addChild(face)
        let roof = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 8)
        roof.fillColor = SKColor(red: 0.86, green: 0.55, blue: 0.48, alpha: 1)
        roof.strokeColor = .clear; roof.position = CGPoint(x: 0, y: h); node.addChild(roof)
        // window band
        for i in 0..<5 {
            let win = SKShapeNode(rectOf: CGSize(width: w * 0.13, height: d * 0.22), cornerRadius: 3)
            win.fillColor = SKColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1); win.strokeColor = .clear
            win.position = CGPoint(x: (CGFloat(i) - 2) * w * 0.17, y: h + d * 0.05); node.addChild(win)
        }
        // pool entrance hint: a small blue rectangle of water at the south face
        let pool = SKShapeNode(rectOf: CGSize(width: w * 0.4, height: d * 0.22), cornerRadius: 4)
        pool.fillColor = SKColor(red: 0.35, green: 0.70, blue: 0.92, alpha: 1); pool.strokeColor = .clear
        pool.position = CGPoint(x: -w * 0.2, y: -d * 0.5 - 14); node.addChild(pool)
        worldNode.addChild(node)
    }

    /// A children's playground: a soft tan play surface, a slide, two swings, and
    /// a sandbox — the cozy heart of the park.
    private func addPlayground(center: Vec2) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 4
        let pad = SKShapeNode(rectOf: CGSize(width: 230, height: 200), cornerRadius: 14)
        pad.fillColor = SKColor(red: 0.85, green: 0.72, blue: 0.52, alpha: 1)
        pad.strokeColor = SKColor(white: 1, alpha: 0.25); pad.lineWidth = 2; node.addChild(pad)
        // slide: a ladder + a sloped chute
        let chute = SKShapeNode(rectOf: CGSize(width: 16, height: 70), cornerRadius: 6)
        chute.fillColor = SKColor(red: 0.95, green: 0.70, blue: 0.30, alpha: 1); chute.strokeColor = .clear
        chute.zRotation = 0.5; chute.position = CGPoint(x: -50, y: 0); node.addChild(chute)
        let top = SKShapeNode(rectOf: CGSize(width: 26, height: 12), cornerRadius: 3)
        top.fillColor = SKColor(red: 0.90, green: 0.40, blue: 0.40, alpha: 1); top.strokeColor = .clear
        top.position = CGPoint(x: -70, y: 26); node.addChild(top)
        // swing set: a frame with two swings
        let frame = SKShapeNode(rectOf: CGSize(width: 90, height: 8), cornerRadius: 3)
        frame.fillColor = SKColor(red: 0.40, green: 0.55, blue: 0.70, alpha: 1); frame.strokeColor = .clear
        frame.position = CGPoint(x: 55, y: 34); node.addChild(frame)
        for dx in [-22.0, 22.0] {
            let rope = SKShapeNode(rectOf: CGSize(width: 3, height: 44))
            rope.fillColor = SKColor(white: 0.3, alpha: 0.8); rope.strokeColor = .clear
            rope.position = CGPoint(x: 55 + CGFloat(dx), y: 12); node.addChild(rope)
            let seat = SKShapeNode(rectOf: CGSize(width: 18, height: 6), cornerRadius: 2)
            seat.fillColor = SKColor(red: 0.30, green: 0.55, blue: 0.40, alpha: 1); seat.strokeColor = .clear
            seat.position = CGPoint(x: 55 + CGFloat(dx), y: -10); node.addChild(seat)
        }
        // sandbox
        let sand = SKShapeNode(rectOf: CGSize(width: 60, height: 44), cornerRadius: 6)
        sand.fillColor = SKColor(red: 0.93, green: 0.84, blue: 0.58, alpha: 1)
        sand.strokeColor = SKColor(red: 0.70, green: 0.50, blue: 0.30, alpha: 1); sand.lineWidth = 3
        sand.position = CGPoint(x: 5, y: -64); node.addChild(sand)
        worldNode.addChild(node)
        for p in [center + Vec2(-50, -20), center + Vec2(55, -30), center + Vec2(0, 60)] { addKid(at: p) }
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
        node.addChild(kenneySprite(kenneyCharacters.randomElement()!, height: 26))
        node.run(.repeatForever(.sequence([                 // jumping, playing
            .moveBy(x: 0, y: 12, duration: 0.24),
            .moveBy(x: 0, y: -12, duration: 0.22),
            .wait(forDuration: Double.random(in: 0.3...1.3)),
        ])))
        worldNode.addChild(node)
    }

    /// A neighborhood church across Montrose on the north: a faked-height nave with
    /// a peaked roof, a tall bell tower, and a round rose window. Original, generic
    /// chapel silhouette — no specific congregation or property referenced.
    private func addChurch(at center: Vec2) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 5
        let w = 200 * scale, d = 150 * scale, h: CGFloat = 120
        let shadow = SKShapeNode(rectOf: CGSize(width: w + 12, height: d + 12), cornerRadius: 6)
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 8, y: -10); node.addChild(shadow)
        let nave = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 4)
        nave.fillColor = SKColor(red: 0.86, green: 0.82, blue: 0.74, alpha: 1)
        nave.strokeColor = SKColor(white: 0, alpha: 0.18); nave.lineWidth = 1; node.addChild(nave)
        let roof = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 4)
        roof.fillColor = SKColor(red: 0.55, green: 0.40, blue: 0.34, alpha: 1)
        roof.strokeColor = .clear; roof.position = CGPoint(x: 0, y: h); node.addChild(roof)
        // bell tower rising above the roofline on the left
        let tower = SKShapeNode(rectOf: CGSize(width: w * 0.26, height: d * 0.7), cornerRadius: 3)
        tower.fillColor = SKColor(red: 0.80, green: 0.76, blue: 0.68, alpha: 1); tower.strokeColor = .clear
        tower.position = CGPoint(x: -w * 0.32, y: h + d * 0.25); node.addChild(tower)
        let spire = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.15, y: 0)); p.addLine(to: CGPoint(x: w * 0.15, y: 0))
            p.addLine(to: CGPoint(x: 0, y: d * 0.4)); p.closeSubpath(); return p
        }())
        spire.fillColor = SKColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 1); spire.strokeColor = .clear
        spire.position = CGPoint(x: -w * 0.32, y: h + d * 0.6); node.addChild(spire)
        // rose window
        let rose = SKShapeNode(circleOfRadius: 12)
        rose.fillColor = SKColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1)
        rose.strokeColor = SKColor(white: 1, alpha: 0.7); rose.lineWidth = 2
        rose.position = CGPoint(x: w * 0.12, y: h + d * 0.1); node.addChild(rose)
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
            Vec2(-400, -600), Vec2(300, -600),       // along Montrose (inside)
            Vec2(-400, 600), Vec2(300, 600),         // along Sunnyside (inside)
            Vec2(-690, -300), Vec2(-690, 300),       // along Western (inside)
            Vec2(450, -400), Vec2(560, 300),         // toward Lincoln (inside)
            Vec2(120, 60), Vec2(-260, 80), Vec2(-200, -600),
        ]
        for (i, h) in homes.enumerated() {
            let ped = Ped(home: h, reactorIndex: i)
            addPerson(to: ped.node)
            ped.node.position = pt(h)
            ped.node.zPosition = 8
            worldNode.addChild(ped.node)
            peds.append(ped)
        }
    }

    private func addPerson(to node: SKNode) {
        let shadow = SKShapeNode(circleOfRadius: 13)
        shadow.fillColor = SKColor(white: 0, alpha: 0.15); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 4, y: -6); node.addChild(shadow)
        node.addChild(kenneySprite(kenneyCharacters.randomElement()!, height: 34))
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
        updateAdventure(dt: dt)
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
        updateBeacon()
    }

    /// Hold the wide establishing shot, then smoothly ease in to follow the bus.
    private func updateCamera() {
        let center = pt(Vec2(10, 0))
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

        // Idle until the ride hands the bus a goal: through the wide establishing
        // shot and the opening "follow the arrow" line, so the bus doesn't drive
        // off and overshoot its first stop. It sets off the moment a target is set.
        if !hasGoal {
            applyMove(&bus, throttle: 0, steer: 0, dt: dt)
            return
        }

        // Follow the perimeter loop, easing off into corners.
        let target = busLoop[busTarget % busLoop.count]
        let dist = bus.position.distance(to: target)
        if dist < 70 { busTarget = (busTarget + 1) % busLoop.count }
        var throttle = dist < 180 ? 0.35 : 1.0
        if shouldStop(bus.position) { throttle = -1.0 }
        if quickStop.state == .running { throttle = -0.5 }   // demo brakes (gently) for the ball
        if challengeDone, elapsed < challengeResumeAt { throttle = -1.0 }   // dwell at the stop
        // Home in on the active episode goal: once near, steer straight at it and
        // ease to a clean stop ON it (inside the arrival radius) so the pickup /
        // drop-off lands. While far, keep following the road loop toward it.
        var steerTo = target
        if let goal = episodeTarget {
            let d = bus.position.distance(to: goal.position)
            if d < 300 { steerTo = goal.position }
            if d < 45 { throttle = -1.0 }
            else if d < 220 { throttle = min(throttle, 0.4) }
        }
        applyMove(&bus, throttle: throttle, steer: bus.steer(toward: steerTo), dt: dt)
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
        // a kid at the north curb of Montrose, about to chase the ball
        kidChaser.position = pt(Vec2(40, -805)); kidChaser.zPosition = 8
        let sh = SKShapeNode(circleOfRadius: 10)
        sh.fillColor = SKColor(white: 0, alpha: 0.14); sh.strokeColor = .clear
        sh.position = CGPoint(x: 3, y: -4); kidChaser.addChild(sh)
        let body = SKShapeNode(circleOfRadius: 11)
        body.fillColor = SKColor(red: 0.95, green: 0.5, blue: 0.3, alpha: 1)
        body.strokeColor = SKColor(white: 0, alpha: 0.2); body.lineWidth = 1; kidChaser.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 4, y: 4); kidChaser.addChild(head)
        worldNode.addChild(kidChaser)

        // the ball, resting by the curb until the challenge arms
        ballNode.fillColor = .white; ballNode.strokeColor = SKColor(white: 0, alpha: 0.4); ballNode.lineWidth = 2
        ballNode.position = pt(Vec2(100, -800)); ballNode.zPosition = 9
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

        // the "Brake!" cue: a bright pill that pulses above the meter while the
        // window is open, so the child knows to act right now.
        let cueBG = SKShapeNode(rectOf: CGSize(width: 110, height: 34), cornerRadius: 17)
        cueBG.fillColor = SKColor(red: 0.92, green: 0.26, blue: 0.28, alpha: 1)
        cueBG.strokeColor = .white; cueBG.lineWidth = 2.5; brakeCue.addChild(cueBG)
        brakeCueLabel.fontSize = 21; brakeCueLabel.fontColor = .white
        brakeCueLabel.verticalAlignmentMode = .center; brakeCueLabel.horizontalAlignmentMode = .center
        brakeCue.addChild(brakeCueLabel)
        brakeCue.zPosition = 27; brakeCue.isHidden = true; worldNode.addChild(brakeCue)
    }

    private func updateChallenge(dt: Double) {
        if quickStop.state == .idle, !challengeDone {
            let b = bus.position
            // Arm only as the bus *approaches the ball*, east of the bus-stop pickup
            // (else it would trigger while stopped boarding Pip and "succeed" for
            // free). The ~160u run-up leaves time to react before the crossing.
            if abs(b.z - challengePoint.z) < 130, b.x > challengePoint.x - 160, b.x < challengePoint.x {
                quickStop.arm()
                startBallRoll()
                meterBG.isHidden = false; meterFill.isHidden = false
                showBrakeCue()
                sayChallenge("qs.lookOut")   // spoken + subtitled prompt: brake now!
            }
        }
        guard quickStop.state == .running else { return }
        quickStop.update(dt: dt, busSpeed: bus.speed)
        layoutMeter()
        if quickStop.state == .success { onChallengeSuccess() }
        else if quickStop.state == .missed { onChallengeMissed() }
    }

    /// Speak (TTS) + subtitle a challenge line in the current language, voiced by
    /// Mom — mirrors how episode lines are presented so it feels of a piece.
    private func sayChallenge(_ lineId: String) {
        let text = dialogue.play(lineId, force: true)
        hud?.subtitle = text
        hud?.speakerName = localizer.string("mom.name", language)
        hud?.speakerColorHex = "#2ea59e"
        subtitleClearAt = elapsed + 3.5
    }

    private func showBrakeCue() {
        brakeCueLabel.text = localizer.string("hud.brake", language)
        brakeCue.isHidden = false
        brakeCue.removeAllActions()
        brakeCue.setScale(1)
        brakeCue.run(.repeatForever(.sequence([
            .scale(to: 1.14, duration: 0.32), .scale(to: 1.0, duration: 0.32),
        ])), withKey: "pulse")
    }

    private func hideBrakeCue() {
        brakeCue.removeAction(forKey: "pulse")
        brakeCue.isHidden = true
    }

    private func startBallRoll() {
        ballNode.removeAllActions()
        ballNode.position = pt(Vec2(100, -800))
        ballNode.run(.group([
            .move(to: pt(Vec2(100, -600)), duration: quickStop.duration + 0.6),   // roll south across Montrose
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
        brakeCue.position = CGPoint(x: p.x, y: p.y + 104)
    }

    private func onChallengeSuccess() {
        challengeDone = true
        challengeResumeAt = elapsed + 4.0          // wait for the kid (and let CI catch it)
        meterBG.isHidden = true; meterFill.isHidden = true
        hideBrakeCue()
        sparkleBurst(at: busNode.position)
        showScore(quickStop.score, at: busNode.position)
        sayChallenge("qs.greatStop")              // praise the safe stop
        kidFetchesBall()                          // the kid happily collects the ball
    }

    private func onChallengeMissed() {
        // No harsh failure: the ball safely rolls clear, the kid waits, and we offer
        // gentle encouragement. The challenge stays un-`done`, so it re-arms when the
        // bus comes back around for another try.
        meterBG.isHidden = true; meterFill.isHidden = true
        hideBrakeCue()
        ballNode.removeAllActions()
        sayChallenge("qs.tryBrake")
        quickStop.reset()
    }

    /// On a clean stop, the waiting kid trots out, scoops up the ball, and hops
    /// happily back to the curb — a warm, harm-free payoff for braking in time.
    private func kidFetchesBall() {
        ballNode.removeAllActions()
        let curb = pt(Vec2(40, -805))
        let ballHome = pt(Vec2(60, -800))
        kidChaser.run(.sequence([
            .move(to: ballNode.position, duration: 0.5),
            .run { [weak self] in self?.ballNode.run(.move(to: ballHome, duration: 0.45)) },
            .move(to: curb, duration: 0.5),
            .repeat(.sequence([.moveBy(x: 0, y: 10, duration: 0.18), .moveBy(x: 0, y: -10, duration: 0.16)]), count: 2),
        ]))
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

    // MARK: - Adventure: load content, run the episode, render the story

    /// Load the bilingual strings from the bundle so the voice + HUD speak real
    /// lines. Falls back to ids (never crashes) if the Content folder is missing.
    private func loadContent() {
        let save = SaveStore().load()
        language = save.language
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Content"),
           let content = try? ContentLoader.load(from: dir) {
            localizer = content.localizer
        }
        dialogue = DialogueDirector(localizer: localizer, language: language, speaker: speaker)
    }

    /// Pip waits at the bus-stop shelter, doing a gentle idle bob until boarding.
    private func buildPassenger() {
        pipNode = makeKidNode(shirt: SKColor(red: 1.0, green: 0.54, blue: 0.24, alpha: 1))
        pipNode.position = pt(Vec2(-200, -625))   // on the curb by the stop shelter (Montrose)
        pipNode.zPosition = 9
        pipNode.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 8, duration: 0.5), .moveBy(x: 0, y: -8, duration: 0.5),
        ])))
        worldNode.addChild(pipNode)
    }

    /// A small child sprite (shadow + coloured body + head), reused for Pip.
    private func makeKidNode(shirt: SKColor) -> SKNode {
        let node = SKNode()
        let shadow = SKShapeNode(circleOfRadius: 11)
        shadow.fillColor = SKColor(white: 0, alpha: 0.14); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 3, y: -4); node.addChild(shadow)
        let body = SKShapeNode(circleOfRadius: 11)
        body.fillColor = shirt; body.strokeColor = SKColor(white: 0, alpha: 0.2); body.lineWidth = 1
        node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 4); node.addChild(head)
        return node
    }

    /// Mark the bottom-right building as the school: a flagpole with a pennant and
    /// a little yellow nameplate, so the drop-off has a clear destination.
    private func buildSchoolSign() {
        let node = SKNode(); node.position = pt(Vec2(-200, 860)); node.zPosition = 6
        let plate = SKShapeNode(rectOf: CGSize(width: 96, height: 30), cornerRadius: 6)
        plate.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
        plate.strokeColor = SKColor(white: 0, alpha: 0.25); plate.lineWidth = 2
        plate.position = CGPoint(x: 0, y: -10); node.addChild(plate)
        for dx in [-26.0, 0.0, 26.0] {     // three "books"/blocks to read as a school
            let book = SKShapeNode(rectOf: CGSize(width: 14, height: 14), cornerRadius: 2)
            book.fillColor = SKColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1); book.strokeColor = .clear
            book.position = CGPoint(x: CGFloat(dx), y: -10); node.addChild(book)
        }
        let pole = SKShapeNode(rectOf: CGSize(width: 5, height: 60), cornerRadius: 2)
        pole.fillColor = SKColor(white: 0.6, alpha: 1); pole.strokeColor = .clear
        pole.position = CGPoint(x: -56, y: 24); node.addChild(pole)
        let flag = SKShapeNode(rectOf: CGSize(width: 34, height: 20), cornerRadius: 3)
        flag.fillColor = SKColor(red: 0.90, green: 0.32, blue: 0.42, alpha: 1); flag.strokeColor = .clear
        flag.position = CGPoint(x: -38, y: 44); node.addChild(flag)
        worldNode.addChild(node)
    }

    /// A floating chevron that hovers above the bus and points at the current
    /// goal — the HUD beacon, in-world so it reads at a glance while driving.
    private func buildBeacon() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16, y: 0))
        path.addLine(to: CGPoint(x: -12, y: 12))
        path.addLine(to: CGPoint(x: -4, y: 0))
        path.addLine(to: CGPoint(x: -12, y: -12))
        path.closeSubpath()
        beaconNode.path = path
        beaconNode.fillColor = SKColor(red: 0.18, green: 0.65, blue: 0.62, alpha: 1)
        beaconNode.strokeColor = .white; beaconNode.lineWidth = 2
        beaconNode.zPosition = 22
        beaconNode.isHidden = true
        worldNode.addChild(beaconNode)
    }

    private func updateBeacon() {
        // Keep the eyes on the brake while the Quick Stop window is open.
        if quickStop.state == .running { beaconNode.isHidden = true; return }
        guard let goal = episodeTarget else { beaconNode.isHidden = true; return }
        beaconNode.isHidden = false
        let from = busNode.position
        let to = pt(goal.position)
        let ang = atan2(to.y - from.y, to.x - from.x)
        beaconNode.position = CGPoint(x: from.x, y: from.y + 96)
        beaconNode.zRotation = ang
    }

    /// Start the ride the moment the camera eases in from the establishing shot.
    private func updateAdventure(dt: Double) {
        guard episodeStarted else {
            if elapsed >= establishHold { startAdventure() }
            return
        }
        runner?.update(dt: dt)
        if subtitleClearAt > 0, elapsed >= subtitleClearAt {
            hud?.subtitle = ""; hud?.speakerName = ""
            subtitleClearAt = -1
        }
    }

    private func startAdventure() {
        episodeStarted = true
        awardedStars = 0
        hud?.stars = 0
        let r = EpisodeRunner(episode: .townFirstRide, world: self) { [weak self] event in
            self?.handleEpisode(event)
        }
        r.arrivalRadius = 55       // generous: the bus eases to a clean stop in the zone
        runner = r
        r.start()
    }

    private func handleEpisode(_ event: EpisodeEvent) {
        switch event {
        case let .speak(lineId, vars):
            let text = dialogue.play(lineId, vars: vars)
            hud?.subtitle = text
            hud?.speakerName = speakerName(forLine: lineId)
            hud?.speakerColorHex = lineId.hasPrefix("pip") ? "#ff8a3d" : "#2ea59e"
            subtitleClearAt = elapsed + 4.5
        case let .setTarget(target):
            episodeTarget = target
            if target != nil { hasGoal = true }   // the bus may now drive
            updateObjective(for: target)
        case .board:
            boardPassenger()
        case let .drop(_, placeId):
            dropPassenger(at: placeId)
        case let .reward(stars, stickerId):
            award(stars: stars)
            sparkleBurst(at: busNode.position)
            showScore(stars, at: busNode.position)
            persistReward(stars: stars, sticker: stickerId)
        case .starSparkle:
            award(stars: 1)
            sparkleBurst(at: busNode.position)
        case .completed:
            hud?.objective = localizer.string("hud.allDone", language)
            episodeTarget = nil
        default:
            break   // awaitChoice / awaitFind are unused in this ride
        }
    }

    private func updateObjective(for target: EpisodeTarget?) {
        guard let target = target else { return }
        switch target.id {
        case "stopA": hud?.objective = localizer.string("hud.pickUpPip", language)
        case "school": hud?.objective = localizer.string("hud.takeToSchool", language)
        default: break
        }
    }

    private func speakerName(forLine lineId: String) -> String {
        let prefix = lineId.split(separator: ".").first.map(String.init) ?? ""
        if prefix == "pip" { return localizer.string("passenger.pip", language) }
        return localizer.string("mom.name", language)
    }

    private func award(stars: Int) {
        awardedStars += max(0, stars)
        hud?.stars = awardedStars
    }

    /// Pip runs to the bus and hops aboard (fade + shrink), with a friendly toot.
    private func boardPassenger() {
        pipNode.removeAllActions()
        pipNode.run(.sequence([
            .group([.move(to: busNode.position, duration: 0.45),
                    .scale(to: 0.2, duration: 0.45),
                    .fadeOut(withDuration: 0.45)]),
            .removeFromParent(),
        ]))
        busNode.run(.sequence([.scale(to: 1.06, duration: 0.1), .scale(to: 1.0, duration: 0.14)]))
        spawnHeart(at: busNode.position)
    }

    /// Pip hops off the bus and skips up to the school door.
    private func dropPassenger(at placeId: String) {
        let pip = makeKidNode(shirt: SKColor(red: 1.0, green: 0.54, blue: 0.24, alpha: 1))
        pip.position = busNode.position
        pip.zPosition = 9
        pip.setScale(0.2)
        worldNode.addChild(pip)
        let door = pt(schoolDoor)
        pip.run(.sequence([
            .scale(to: 1.0, duration: 0.25),
            .move(to: door, duration: 1.3),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
        spawnHeart(at: busNode.position)
    }

    private func persistReward(stars: Int, sticker: String?) {
        let store = SaveStore()
        var save = store.load()
        save.award(stars: stars)
        if let id = sticker { save.grant(sticker: id) }
        save.markComplete(episode: "town-first-ride")
        store.save(save)
    }

    // MARK: - EpisodeWorld (the scene is the world the runner observes)

    var busPosition: Vec2 { bus.position }
    var busSpeed: Double { bus.speed }
    func position(ofPlace placeId: String) -> Vec2? {
        placeId == "school" ? schoolPlace : townMap.position(ofPlace: placeId)
    }
    func position(ofLight lightId: String) -> Vec2? { light.position }
    func lightState(_ lightId: String) -> TrafficLight.State { light.state }
    func consumeDiscreteTurn() -> InputIntents.DiscreteTurn { .none }
}
