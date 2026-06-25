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
    private enum BuildingKind { case apartments, restaurant, shop, school, salon, barber }
    private struct Building { var center: Vec2; var size: CGSize; var height: CGFloat; var kind: BuildingKind }
    // The "charm anchor" buildings (awnings, signs, the school) sit on the street
    // frontage; the procedural streetwall (buildStreetwalls) fills in around them
    // with plain side-by-side blocks. Frontage lines sit one `buildingSetback` out
    // from each road (curb + parkway + wide sidewalk).
    private let buildings: [Building] = [
        // West of Western Ave: apartments along the frontage.
        Building(center: Vec2(-1040, -360), size: CGSize(width: 220, height: 300), height: 150, kind: .apartments),
        Building(center: Vec2(-1040, 60), size: CGSize(width: 220, height: 260), height: 120, kind: .apartments),
        // South of the south road: the school + a restaurant.
        Building(center: Vec2(-200, 975), size: CGSize(width: 280, height: 220), height: 100, kind: .school),
        Building(center: Vec2(220, 960), size: CGSize(width: 200, height: 180), height: 90, kind: .restaurant),
        // North of the north road: a barber + a salon (the church is its own builder).
        Building(center: Vec2(-680, -940), size: CGSize(width: 150, height: 150), height: 80, kind: .barber),
        Building(center: Vec2(-500, -940), size: CGSize(width: 150, height: 150), height: 80, kind: .salon),
    ]
    /// Footprints (centre, half-width, half-depth) of everything already placed —
    /// the streetwall skips these, and trees avoid them.
    private var placedFootprints: [(c: Vec2, hw: Double, hd: Double)] = []

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
    private let wideZoom: CGFloat = 3.7    // wide enough to take in the whole neighborhood block
    // Closer follow zoom: the camera sits right above the bus so it reads big on
    // screen (especially on iPhone, where the 16:9 canvas is letterboxed small).
    private let closeZoom: CGFloat = 0.62
    // A brief wide shot of the town, then ease in to follow the bus as the ride
    // begins. Kept short so the whole first ride fits a CI capture window.
    // The intro flyover is short for players. CI sets AMELIA_OVERVIEW=1 (via
    // SIMCTL_CHILD_) to hold the wide shot long enough that the recordVideo capture
    // window — which only opens several seconds after launch — lands on it.
    private let establishHold: TimeInterval =
        ProcessInfo.processInfo.environment["AMELIA_OVERVIEW"] != nil ? 24.0 : 4.0
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

    // MARK: - Music & sound pass.
    // A calm bed + always-on nature ambience, a bee buzz that swells near the
    // flowers, an engine hum that follows the bus's speed, and discrete cues
    // (honk, crossing wait/go, the light countdown, a passing car). The world also
    // gets wildlife — birds, squirrels, rabbits, bees — that chirp/scurry/hop and
    // react to the horn. All gentle, all mixed below the spoken voice.
    private let audio = ProceduralAudio()
    private var birds: [SKNode] = []
    private var squirrels: [SKNode] = []
    private var rabbits: [SKNode] = []
    private var beeClusters: [Vec2] = []
    private var critterTimer: TimeInterval = 0
    private var nextCritterDelay: TimeInterval = 3.0
    private var carWasNear = false
    private var prevLightState: TrafficLight.State = .green
    private var lastCountdownSecond = -1
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

    // Stoplights stand at the four park corners (not in the road). One drives the
    // bus's stop logic; all four render the same phase. Mostly green so the ride
    // flows. `light.position` is the NE corner.
    private var light = TrafficLight(id: "main", position: Vec2(550, -700), phase: 0,
                                     green: 6, yellow: 1.5, red: 3)
    private var cornerLamps: [(red: SKShapeNode, yellow: SKShapeNode, green: SKShapeNode)] = []

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
        buildGroundTexture()
        buildRoads()
        buildRoadWear()
        buildBuildings()   // before trees, so the lining trees can avoid building footprints
        buildTrees()
        buildScenery()
        buildParkedCars()
        buildPeds()
        buildParkLife()
        buildWildlife()
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

        // Roll the calm driving bed + the living-neighborhood ambience.
        audio.setMusic(.driving)
        audio.setAmbience(true)
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
        // A continuous concrete sidewalk flush against both edges of every road, so
        // the walkways read as attached to the streets (not floating in the grass).
        for s in net.segments { addSidewalkStrip(s.a, s.b, width: s.width) }

        // Mid-block pedestrian crossings at the bus stop and the school.
        addCrosswalk(at: Vec2(-200, -700), along: Vec2(1, 0), roadWidth: 110)   // bus stop (north road)
        addCrosswalk(at: Vec2(-200, 700), along: Vec2(1, 0), roadWidth: 110)    // school (south road)
        // At each park-corner stoplight: a crosswalk pulled in tight to the
        // intersection, with a bold stop bar just behind it so it's clear where
        // the bus is meant to stop for the light.
        for a in cornerApproaches { addApproachMarkings(corner: a.corner, travel: a.travel, roadWidth: 110) }

        // The park corners get stoplights (built separately). Every *other* grid
        // junction is a four-way stop with a little stop sign.
        for c in net.intersections()
        where !RoadNetwork.wellesCorners.contains(where: { $0.distance(to: c) < 1 }) {
            addFourWayStop(at: c)
        }
    }

    /// A continuous concrete sidewalk band just outside both edges of a road.
    // Street cross-section (per side): road | curb | a grass PARKWAY (with the
    // lining trees) | a WIDE sidewalk that buildings sit flush against.
    private let parkwayWidth = 46.0
    private let sidewalkWidth = 40.0

    private func addSidewalkStrip(_ a: Vec2, _ b: Vec2, width: Double) {
        let d = b - a; let len = d.length
        guard len > 1 else { return }
        let perp = Vec2(-d.z / len, d.x / len)
        for side in [-1.0, 1.0] {
            // wide sidewalk set back from the curb by the green parkway
            let off = perp * (side * (width / 2 + parkwayWidth + sidewalkWidth / 2))
            let strip = roadLine(a + off, b + off, width: CGFloat(sidewalkWidth) * scale,
                                 color: SKColor(red: 0.82, green: 0.81, blue: 0.79, alpha: 1), z: -0.1)
            worldNode.addChild(strip)
            // a thin curb line at the road edge
            let curbOff = perp * (side * (width / 2 + 3))
            let curb = roadLine(a + curbOff, b + curbOff, width: 3,
                                color: SKColor(white: 0.72, alpha: 0.6), z: -0.05)
            worldNode.addChild(curb)
        }
    }

    /// The street-facing edge distance from a road centerline out to the building
    /// line (curb + parkway + sidewalk) — where a streetwall building's front sits.
    private var buildingSetback: Double { 55 + parkwayWidth + sidewalkWidth }

    /// A small stop sign on a post, nudged onto the interior curb of a corner.
    private func addFourWayStop(at v: Vec2) {
        let inset = Vec2(v.x > 0 ? -78 : 78, v.z > 0 ? -78 : 78)
        let node = SKNode(); node.position = pt(v + inset); node.zPosition = 7
        let post = SKShapeNode(rectOf: CGSize(width: 4, height: 26))
        post.fillColor = SKColor(white: 0.5, alpha: 1); post.strokeColor = .clear
        post.position = CGPoint(x: 0, y: -14); node.addChild(post)
        let sign = SKShapeNode(path: polygonPath(sides: 8, radius: 16))
        sign.fillColor = SKColor(red: 0.82, green: 0.16, blue: 0.18, alpha: 1)
        sign.strokeColor = .white; sign.lineWidth = 2.5; node.addChild(sign)
        let bar = SKShapeNode(rectOf: CGSize(width: 18, height: 3))
        bar.fillColor = .white; bar.strokeColor = .clear; node.addChild(bar)
        worldNode.addChild(node)
    }

    /// A square of clean asphalt over a road junction. Drawn ABOVE the lane
    /// markings (edge lines + center dashes) so those don't criss-cross through the
    /// intersection — real junctions are blank asphalt in the box. Crosswalks and
    /// stop bars sit above this again, so they still read.
    private func addIntersectionPad(at v: Vec2, width: CGFloat) {
        let pad = SKShapeNode(rectOf: CGSize(width: width * scale + 8, height: width * scale + 8), cornerRadius: 6)
        pad.position = pt(v)
        pad.fillColor = SKColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)   // matches the road surface
        pad.strokeColor = .clear
        pad.zPosition = 1.2
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
        let span = 38.0                            // total length painted along travel (a thin band)
        for i in 0..<bars {
            let t = (Double(i) / Double(bars - 1) - 0.5) * span
            let mid = center + travel * t
            let line = roadLine(mid - across * (roadWidth / 2 - 8),
                                mid + across * (roadWidth / 2 - 8),
                                width: 5, color: SKColor(white: 0.95, alpha: 0.85), z: 1.4)
            line.lineCap = .butt
            worldNode.addChild(line)
        }
    }

    /// For each park corner: the world direction the bus is TRAVELLING as it
    /// reaches that corner on its clockwise tour. Drives the approach crosswalk +
    /// stop-bar placement so they sit on the lane the bus actually drives.
    private let cornerApproaches: [(corner: Vec2, travel: Vec2)] = [
        (Vec2(-800, -700), Vec2(0, -1)),          // NW: heading north up Western
        (Vec2(550, -700), Vec2(1, 0)),            // NE: heading east along Montrose
        (Vec2(820, 700), Vec2(0.189, 0.982)),     // SE: down the Lincoln diagonal
        (Vec2(-800, 700), Vec2(-1, 0)),           // SW: heading west along Sunnyside
    ]

    /// Tight intersection markings on the bus's approach leg: a crosswalk just
    /// outside the intersection box, and a bold stop bar a short way behind it —
    /// the clear "stop here" line in front of the crossing.
    private func addApproachMarkings(corner: Vec2, travel: Vec2, roadWidth: Double) {
        let padHalf = 55.0
        let cross = corner - travel * (padHalf + 22)   // crosswalk hugs the intersection
        addCrosswalk(at: cross, along: travel, roadWidth: roadWidth)
        let stop = corner - travel * (padHalf + 52)    // stop bar a bit behind the crosswalk
        addStopLine(at: stop, along: travel, roadWidth: roadWidth)
    }

    /// A single bold white stop bar across the road, perpendicular to travel.
    private func addStopLine(at center: Vec2, along dir: Vec2, roadWidth: Double) {
        let len = dir.length
        guard len > 1e-6 else { return }
        let travel = Vec2(dir.x / len, dir.z / len)
        let across = Vec2(-travel.z, travel.x)
        let bar = roadLine(center - across * (roadWidth / 2 - 6),
                           center + across * (roadWidth / 2 - 6),
                           width: 9, color: SKColor(white: 0.95, alpha: 0.9), z: 1.45)
        bar.lineCap = .butt
        worldNode.addChild(bar)
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

    /// Break up the flat grass: soft organic tonal blobs scattered over the whole
    /// map, plus gentle mowing stripes across the park lawn. All deterministic (a
    /// seeded RNG) so CI captures stay comparable, and drawn below the roads so the
    /// streets/sidewalks sit on top. Decorative only.
    private func buildGroundTexture() {
        var s: UInt64 = 0x00C0_FFEE
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407
                               return Double((s >> 40) & 0xFFFF) / 65535.0 }
        let minX = -1500.0, maxX = 1500.0, minZ = -1450.0, maxZ = 1450.0
        // organic mottling
        for _ in 0..<80 {
            let x = minX + rnd() * (maxX - minX)
            let z = minZ + rnd() * (maxZ - minZ)
            let r = 90 + rnd() * 200
            let blob = SKShapeNode(ellipseOf: CGSize(width: CGFloat(r) * scale, height: CGFloat(r * 0.7) * scale))
            blob.fillColor = rnd() > 0.5
                ? SKColor(red: 0.52, green: 0.78, blue: 0.46, alpha: 0.28)
                : SKColor(red: 0.39, green: 0.65, blue: 0.36, alpha: 0.24)
            blob.strokeColor = .clear
            blob.position = pt(Vec2(x, z)); blob.zPosition = -0.7
            worldNode.addChild(blob)
        }
        // park mowing stripes (only visible on the exposed lawn — roads/buildings
        // draw over them). Confined to the park block.
        let pMinX = -800.0, pMaxX = 820.0
        var z = -660.0
        var band = 0
        while z < 680 {
            if band % 2 == 0 {
                let stripe = SKShapeNode(rectOf: CGSize(width: CGFloat(pMaxX - pMinX) * scale, height: 46 * scale))
                stripe.fillColor = SKColor(red: 1, green: 1, blue: 0.9, alpha: 0.06)
                stripe.strokeColor = .clear
                stripe.position = pt(Vec2((pMinX + pMaxX) / 2, z)); stripe.zPosition = -0.6
                worldNode.addChild(stripe)
            }
            z += 46; band += 1
        }
    }

    /// Subtle asphalt texture on the streets near the park (where the camera lives):
    /// two faint tire-wear tracks down the lanes plus a few mottled patches, under
    /// the lane markings. Deterministic; decorative only.
    private func buildRoadWear() {
        var s: UInt64 = 0x0000_5EED
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407
                               return Double((s >> 40) & 0xFFFF) / 65535.0 }
        for seg in net.segments {
            let mid = (seg.a + seg.b) * 0.5
            guard abs(mid.x) < 1200, abs(mid.z) < 1200 else { continue }
            let d = seg.b - seg.a; let len = d.length
            guard len > 60 else { continue }
            let dir = Vec2(d.x / len, d.z / len)
            let perp = Vec2(-dir.z, dir.x)
            // tire-wear tracks (darken the asphalt where wheels run)
            for lane in [seg.width * 0.22, -seg.width * 0.22] {
                let wear = roadLine(seg.a + perp * lane, seg.b + perp * lane,
                                    width: CGFloat(seg.width) * 0.26 * scale,
                                    color: SKColor(white: 0, alpha: 0.05), z: 0.45)
                worldNode.addChild(wear)
            }
            // a few mottled patches / faint stains
            for _ in 0..<(2 + Int(rnd() * 3)) {
                let p = seg.a + dir * (rnd() * len) + perp * ((rnd() - 0.5) * seg.width * 0.7)
                let patch = SKShapeNode(ellipseOf: CGSize(width: CGFloat(24 + rnd() * 44) * scale,
                                                          height: CGFloat(16 + rnd() * 22) * scale))
                patch.fillColor = SKColor(white: rnd() > 0.5 ? 0 : 1, alpha: 0.045)
                patch.strokeColor = .clear
                patch.position = pt(p)
                patch.zRotation = CGFloat(atan2(-dir.z, dir.x))
                patch.zPosition = 0.4
                worldNode.addChild(patch)
            }
        }
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
    private let buildingPalettes: [(wall: SKColor, roof: SKColor, win: SKColor)] = [
        (SKColor(red: 0.74, green: 0.52, blue: 0.46, alpha: 1),
         SKColor(red: 0.88, green: 0.68, blue: 0.60, alpha: 1),
         SKColor(red: 0.97, green: 0.93, blue: 0.70, alpha: 1)),
        (SKColor(red: 0.52, green: 0.60, blue: 0.72, alpha: 1),
         SKColor(red: 0.70, green: 0.78, blue: 0.88, alpha: 1),
         SKColor(red: 0.98, green: 0.96, blue: 0.76, alpha: 1)),
        (SKColor(red: 0.70, green: 0.66, blue: 0.56, alpha: 1),
         SKColor(red: 0.87, green: 0.83, blue: 0.74, alpha: 1),
         SKColor(red: 0.58, green: 0.80, blue: 0.95, alpha: 1)),
        (SKColor(red: 0.62, green: 0.68, blue: 0.60, alpha: 1),
         SKColor(red: 0.78, green: 0.83, blue: 0.74, alpha: 1),
         SKColor(red: 0.96, green: 0.90, blue: 0.62, alpha: 1)),
    ]

    private func buildBuildings() {
        for (i, b) in buildings.enumerated() {
            placedFootprints.append((b.center, Double(b.size.width) / 2, Double(b.size.height) / 2))
            drawBuilding(b, paletteIndex: i)
        }
        buildStreetwalls()
    }

    /// Draw one faked-height building (body + warm windows + roof + kind charm).
    private func drawBuilding(_ b: Building, paletteIndex: Int) {
        let pal = buildingPalettes[paletteIndex % buildingPalettes.count]
        let node = SKNode()
        node.position = pt(b.center)
        node.zPosition = 5
        let w = b.size.width * scale, d = b.size.height * scale
        let h = b.height
        do {
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

            addWallShading(to: node, w: w, d: d, h: h)

            // windows across the exposed front face (the lower `h` band). Some are
            // warm-lit (a cozy golden glow), the rest cool glass — each gets a frame
            // + mullion so the buildings feel lived-in rather than flat.
            let cols = max(2, Int(w / 90))
            let rows = max(1, Int(h / 60))
            let lit = SKColor(red: 1.0, green: 0.86, blue: 0.46, alpha: 1)
            let glass = SKColor(red: 0.66, green: 0.82, blue: 0.95, alpha: 1)
            for cx in 0..<cols {
                for ry in 0..<rows {
                    let wW = w / CGFloat(cols) * 0.52, wH = h / CGFloat(rows) * 0.52
                    let px = -w / 2 + (CGFloat(cx) + 0.5) * (w / CGFloat(cols))
                    let py = -d / 2 + (CGFloat(ry) + 0.5) * (h / CGFloat(rows))
                    let isLit = (cx + ry) % 3 == 0
                    if isLit {   // warm spill of light around a lit window
                        let glow = SKShapeNode(circleOfRadius: wW * 0.55)
                        glow.fillColor = SKColor(red: 1, green: 0.85, blue: 0.42, alpha: 0.18)
                        glow.strokeColor = .clear; glow.position = CGPoint(x: px, y: py); node.addChild(glow)
                    }
                    let win = SKShapeNode(rectOf: CGSize(width: wW, height: wH), cornerRadius: 2)
                    win.fillColor = isLit ? lit : glass
                    win.strokeColor = SKColor(white: 0.18, alpha: 0.35); win.lineWidth = 1.5
                    win.position = CGPoint(x: px, y: py); node.addChild(win)
                    let mull = SKShapeNode(rectOf: CGSize(width: wW, height: 1.2))
                    mull.fillColor = SKColor(white: 0.18, alpha: 0.3); mull.strokeColor = .clear
                    mull.position = CGPoint(x: px, y: py); node.addChild(mull)
                }
            }

            // roof cap on top — parapet, lighter inset deck, and rooftop props
            addRoofDetail(to: node, w: w, d: d, h: h, roof: pal.roof,
                          seed: UInt64(bitPattern: Int64(b.center.x * 131 + b.center.z * 977)))

            decorateBuilding(node, kind: b.kind, w: w, d: d, h: h)
            worldNode.addChild(node)
        }
    }

    /// Facade depth without changing the footprint: a grounding shadow stacked at
    /// the base (sits the building on the sidewalk) and a crisp highlight along the
    /// roofline (the top edge of the visible wall).
    private func addWallShading(to node: SKNode, w: CGFloat, d: CGFloat, h: CGFloat) {
        let top = h - d / 2, bottom = -d / 2
        for i in 0..<3 {
            let bandH: CGFloat = 13
            let a = [0.16, 0.09, 0.04][i]
            let band = SKShapeNode(rectOf: CGSize(width: w, height: bandH), cornerRadius: 2)
            band.fillColor = SKColor(white: 0, alpha: CGFloat(a)); band.strokeColor = .clear
            band.position = CGPoint(x: 0, y: bottom + bandH * (CGFloat(i) + 0.5) * 0.85)
            band.zPosition = 0.05; node.addChild(band)
        }
        let hl = SKShapeNode(rectOf: CGSize(width: w - 4, height: 2.5))
        hl.fillColor = SKColor(white: 1, alpha: 0.16); hl.strokeColor = .clear
        hl.position = CGPoint(x: 0, y: top - 2); hl.zPosition = 0.05; node.addChild(hl)
    }

    /// A richer rooftop — the surface most visible from top-down. A dark-edged
    /// parapet lip, a slightly lighter inset deck with a soft sheen + directional
    /// shadow, and a few deterministic props (AC units, vents, an occasional water
    /// tank). The seed is derived from the footprint so CI captures stay stable.
    private func addRoofDetail(to node: SKNode, w: CGFloat, d: CGFloat, h: CGFloat,
                               roof: SKColor, seed: UInt64) {
        var s = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func rnd() -> CGFloat {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Int((s >> 40) & 0xFFFF)) / 65535.0
        }
        let cy = h

        let base = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 6)
        base.fillColor = roof; base.strokeColor = SKColor(white: 0, alpha: 0.28); base.lineWidth = 2.5
        base.position = CGPoint(x: 0, y: cy); node.addChild(base)
        let deck = SKShapeNode(rectOf: CGSize(width: w - 16, height: d - 16), cornerRadius: 4)
        deck.fillColor = roof; deck.strokeColor = SKColor(white: 0, alpha: 0.14); deck.lineWidth = 1.5
        deck.position = CGPoint(x: 0, y: cy); node.addChild(deck)
        let sheen = SKShapeNode(rectOf: CGSize(width: w - 16, height: d - 16), cornerRadius: 4)
        sheen.fillColor = SKColor(white: 1, alpha: 0.06); sheen.strokeColor = .clear
        sheen.position = CGPoint(x: 0, y: cy); node.addChild(sheen)
        let shade = SKShapeNode(rectOf: CGSize(width: (w - 16) * 0.5, height: d - 16))
        shade.fillColor = SKColor(white: 0, alpha: 0.06); shade.strokeColor = .clear
        shade.position = CGPoint(x: (w - 16) * 0.25, y: cy); node.addChild(shade)

        let innerW = max(10, w - 34), innerD = max(10, d - 34)
        func spot() -> CGPoint { CGPoint(x: (rnd() - 0.5) * innerW, y: cy + (rnd() - 0.5) * innerD) }

        for _ in 0..<(1 + Int(rnd() * 2.99)) {       // 1–3 AC units
            let uw = 16 + rnd() * 10, ud = 13 + rnd() * 7
            let p = spot()
            let box = SKShapeNode(rectOf: CGSize(width: uw, height: ud), cornerRadius: 2)
            box.fillColor = SKColor(white: 0.63, alpha: 1)
            box.strokeColor = SKColor(white: 0, alpha: 0.3); box.lineWidth = 1
            box.position = p; box.zPosition = 0.2; node.addChild(box)
            let fan = SKShapeNode(circleOfRadius: min(uw, ud) * 0.28)
            fan.fillColor = SKColor(white: 0.5, alpha: 1)
            fan.strokeColor = SKColor(white: 0.25, alpha: 0.5); fan.lineWidth = 1
            fan.position = p; fan.zPosition = 0.21; node.addChild(fan)
        }
        for _ in 0..<2 {                              // vent pipes
            let vent = SKShapeNode(circleOfRadius: 3.5)
            vent.fillColor = SKColor(white: 0.4, alpha: 1); vent.strokeColor = .clear
            vent.position = spot(); vent.zPosition = 0.2; node.addChild(vent)
        }
        if rnd() > 0.55 {                             // occasional water tank
            let p = spot()
            let legs = SKShapeNode(rectOf: CGSize(width: 22, height: 22))
            legs.fillColor = SKColor(white: 0, alpha: 0.12); legs.strokeColor = .clear
            legs.position = p; legs.zPosition = 0.2; node.addChild(legs)
            let tank = SKShapeNode(circleOfRadius: 13)
            tank.fillColor = SKColor(red: 0.55, green: 0.43, blue: 0.34, alpha: 1)
            tank.strokeColor = SKColor(white: 0, alpha: 0.3); tank.lineWidth = 1.5
            tank.position = CGPoint(x: p.x, y: p.y + 3); tank.zPosition = 0.25; node.addChild(tank)
        }
    }

    /// True if a candidate footprint doesn't collide with anything already placed.
    private func footprintFree(_ c: Vec2, w: Double, d: Double) -> Bool {
        for f in placedFootprints
        where abs(c.x - f.c.x) < f.hw + w / 2 + 12 && abs(c.z - f.c.z) < f.hd + d / 2 + 12 {
            return false
        }
        return true
    }

    /// Fill the street frontages with a streetwall of side-by-side buildings flush
    /// to the wide sidewalk, leaving alleys here and there and gaps at the cross
    /// streets. The hand-placed charm anchors are skipped (drawn already).
    private func buildStreetwalls() {
        // reserve the church footprint (drawn later in buildScenery) so the row
        // leaves a gap for it on the north frontage
        placedFootprints.append((Vec2(-260, -945), 110, 85))
        addCornerRestaurant()   // place this special first so the row leaves room
        streetRow(horizontal: true, frontEdge: -700 - buildingSetback, from: -1230, to: 470)  // north
        streetRow(horizontal: true, frontEdge: 700 + buildingSetback, from: -1230, to: 720)   // south
        streetRow(horizontal: false, frontEdge: -800 - buildingSetback, from: -600, to: 600)  // west
    }

    private func streetRow(horizontal: Bool, frontEdge: Double, from: Double, to: Double) {
        let cross = [-800.0, -130.0, 550.0]   // cross streets cut the block — leave gaps
        let widths = [150.0, 170.0, 190.0, 210.0], depths = [130.0, 140.0, 160.0]
        let heights: [CGFloat] = [70, 90, 110, 130], gaps = [8.0, 10.0, 38.0]
        var p = from
        while p < to {
            let w = widths.randomElement()!, depth = depths.randomElement()!
            let along = p + w / 2
            if cross.contains(where: { abs($0 - along) < w / 2 + 70 }) { p += 90; continue }
            let center = horizontal
                ? Vec2(along, frontEdge < 0 ? frontEdge - depth / 2 : frontEdge + depth / 2)
                : Vec2(frontEdge - depth / 2, along)
            if footprintFree(center, w: w, d: depth) {
                let kind: BuildingKind = Int.random(in: 0..<4) == 0 ? .shop : .apartments
                let b = Building(center: center, size: CGSize(width: w, height: depth),
                                 height: heights.randomElement()!, kind: kind)
                drawBuilding(b, paletteIndex: Int(abs(along) / 57))
                placedFootprints.append((center, w / 2, depth / 2))
            }
            p += w + gaps.randomElement()!
        }
    }

    /// The corner restaurant (north road × Lincoln) with outdoor café seating set
    /// out on the wide sidewalk in front.
    private func addCornerRestaurant() {
        let c = Vec2(450, -700 - buildingSetback - 75)
        placedFootprints.append((c, 100, 75))
        drawBuilding(Building(center: c, size: CGSize(width: 200, height: 150), height: 85, kind: .restaurant),
                     paletteIndex: 0)
        for dx in [-66.0, 0.0, 66.0] { addCafeTable(at: c + Vec2(dx, 122)) }   // on the sidewalk
    }

    private func addCafeTable(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 6
        for cx in [-15.0, 15.0] {
            let chair = SKShapeNode(circleOfRadius: 6)
            chair.fillColor = SKColor(white: 0.55, alpha: 1); chair.strokeColor = .clear
            chair.position = CGPoint(x: cx, y: 0); node.addChild(chair)
        }
        let table = SKShapeNode(circleOfRadius: 9)
        table.fillColor = SKColor(white: 0.92, alpha: 1); table.strokeColor = SKColor(white: 0, alpha: 0.2)
        table.lineWidth = 1; node.addChild(table)
        let umbrella = SKShapeNode(path: polygonPath(sides: 6, radius: 26))
        umbrella.fillColor = [SKColor(red: 0.88, green: 0.34, blue: 0.32, alpha: 1),
                              SKColor(red: 0.30, green: 0.62, blue: 0.60, alpha: 1),
                              SKColor(red: 0.95, green: 0.78, blue: 0.32, alpha: 1)].randomElement()!
        umbrella.strokeColor = SKColor(white: 1, alpha: 0.5); umbrella.lineWidth = 1.5
        umbrella.position = CGPoint(x: 0, y: 6); umbrella.zPosition = 1; node.addChild(umbrella)
        worldNode.addChild(node)
    }

    /// Per-building charm on the visible street face: awnings + an iconic sign for
    /// the shops, a flag + clock + doors for the school, a stoop + balconies for the
    /// apartments. Icons (mug/bag/bell) stay wordless so pre-readers "get" them and
    /// nothing needs translating.
    private func decorateBuilding(_ node: SKNode, kind: BuildingKind, w: CGFloat, d: CGFloat, h: CGFloat) {
        let street = -d / 2           // front edge of the footprint (toward the camera)
        switch kind {
        case .restaurant:
            addAwning(to: node, width: w * 0.82, y: street + 26,
                      base: SKColor(red: 0.86, green: 0.30, blue: 0.32, alpha: 1))
            addDoor(to: node, w: w, street: street, color: SKColor(red: 0.45, green: 0.30, blue: 0.22, alpha: 1))
            addSign(to: node, at: CGPoint(x: w * 0.34, y: h * 0.45)) { self.mugIcon() }
        case .shop:
            addAwning(to: node, width: w * 0.82, y: street + 26,
                      base: SKColor(red: 0.24, green: 0.62, blue: 0.60, alpha: 1))
            addDoor(to: node, w: w, street: street, color: SKColor(red: 0.40, green: 0.28, blue: 0.20, alpha: 1))
            addSign(to: node, at: CGPoint(x: w * 0.34, y: h * 0.45)) { self.bagIcon() }
        case .school:
            addDoubleDoors(to: node, w: w, street: street)
            addClock(to: node, at: CGPoint(x: 0, y: h * 0.55))
            addFlag(to: node, at: CGPoint(x: -w * 0.34, y: h + d * 0.35))
            addSign(to: node, at: CGPoint(x: w * 0.34, y: h * 0.5)) { self.bellIcon() }
        case .apartments:
            addDoor(to: node, w: w, street: street, color: SKColor(red: 0.40, green: 0.42, blue: 0.50, alpha: 1))
            for ry in 0..<2 {            // simple balcony rails on the front face
                let rail = SKShapeNode(rectOf: CGSize(width: w * 0.7, height: 5), cornerRadius: 2)
                rail.fillColor = SKColor(white: 0.25, alpha: 0.5); rail.strokeColor = .clear
                rail.position = CGPoint(x: 0, y: street + 36 + CGFloat(ry) * 52); node.addChild(rail)
            }
        case .salon:
            addAwning(to: node, width: w * 0.8, y: street + 26,
                      base: SKColor(red: 0.85, green: 0.45, blue: 0.62, alpha: 1))
            addDoor(to: node, w: w, street: street, color: SKColor(red: 0.45, green: 0.30, blue: 0.34, alpha: 1))
            addSign(to: node, at: CGPoint(x: w * 0.32, y: h * 0.5)) { self.scissorsIcon() }
        case .barber:
            addDoor(to: node, w: w, street: street, color: SKColor(red: 0.30, green: 0.32, blue: 0.40, alpha: 1))
            addBarberPole(to: node, at: CGPoint(x: w * 0.30, y: street + 30))
            addSign(to: node, at: CGPoint(x: -w * 0.30, y: h * 0.5)) { self.scissorsIcon() }
        }
    }

    /// A spinning-stripe barber pole beside the door.
    private func addBarberPole(to node: SKNode, at p: CGPoint) {
        let pole = SKShapeNode(rectOf: CGSize(width: 12, height: 40), cornerRadius: 6)
        pole.fillColor = .white; pole.strokeColor = SKColor(white: 0, alpha: 0.25); pole.lineWidth = 1.5
        pole.position = p; pole.zPosition = 1.5; node.addChild(pole)
        let stripes = SKNode(); stripes.position = p; stripes.zPosition = 1.6
        let crop = SKCropNode(); let mask = SKShapeNode(rectOf: CGSize(width: 12, height: 40), cornerRadius: 6)
        mask.fillColor = .white; crop.maskNode = mask
        for i in -3...3 {
            let s = SKShapeNode(rectOf: CGSize(width: 20, height: 5))
            s.fillColor = i % 2 == 0 ? SKColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1)
                                     : SKColor(red: 0.2, green: 0.35, blue: 0.8, alpha: 1)
            s.strokeColor = .clear; s.zRotation = 0.7; s.position = CGPoint(x: 0, y: CGFloat(i) * 8)
            crop.addChild(s)
        }
        crop.run(.repeatForever(.sequence([.moveBy(x: 0, y: 16, duration: 0.8), .moveBy(x: 0, y: -16, duration: 0)])))
        stripes.addChild(crop); node.addChild(stripes)
    }

    private func scissorsIcon() -> SKNode {
        let n = SKNode()
        for s in [-1.0, 1.0] {       // two blades crossing
            let blade = SKShapeNode(rectOf: CGSize(width: 4, height: 18), cornerRadius: 2)
            blade.fillColor = SKColor(white: 0.75, alpha: 1); blade.strokeColor = .clear
            blade.zRotation = CGFloat(s) * 0.32; blade.position = CGPoint(x: CGFloat(s) * 3, y: 2); n.addChild(blade)
            let ring = SKShapeNode(circleOfRadius: 4)
            ring.fillColor = .clear; ring.strokeColor = SKColor(red: 0.3, green: 0.45, blue: 0.8, alpha: 1); ring.lineWidth = 2
            ring.position = CGPoint(x: CGFloat(s) * 5, y: -10); n.addChild(ring)
        }
        return n
    }

    /// A scalloped, striped shop awning over the storefront.
    private func addAwning(to node: SKNode, width: CGFloat, y: CGFloat, base: SKColor) {
        let awn = SKNode(); awn.position = CGPoint(x: 0, y: y); awn.zPosition = 1
        let height: CGFloat = 20
        let n = max(4, Int(width / 22)); let sw = width / CGFloat(n)
        for i in 0..<n {
            let col = i % 2 == 0 ? base : SKColor(white: 0.97, alpha: 1)
            let stripe = SKShapeNode(rectOf: CGSize(width: sw, height: height))
            stripe.fillColor = col; stripe.strokeColor = .clear
            stripe.position = CGPoint(x: -width / 2 + (CGFloat(i) + 0.5) * sw, y: 0); awn.addChild(stripe)
            let scallop = SKShapeNode(circleOfRadius: sw * 0.5)
            scallop.fillColor = col; scallop.strokeColor = .clear
            scallop.position = CGPoint(x: stripe.position.x, y: -height / 2); awn.addChild(scallop)
        }
        let trim = SKShapeNode(rectOf: CGSize(width: width, height: 4))
        trim.fillColor = SKColor(white: 0, alpha: 0.18); trim.strokeColor = .clear
        trim.position = CGPoint(x: 0, y: height / 2); awn.addChild(trim)
        node.addChild(awn)
    }

    /// A hanging sign placard with a little icon drawn by `icon`.
    private func addSign(to node: SKNode, at p: CGPoint, icon: () -> SKNode) {
        let board = SKShapeNode(rectOf: CGSize(width: 42, height: 32), cornerRadius: 6)
        board.fillColor = SKColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        board.strokeColor = SKColor(red: 0.45, green: 0.32, blue: 0.20, alpha: 1); board.lineWidth = 2.5
        board.position = p; board.zPosition = 2
        let arm = SKShapeNode(rectOf: CGSize(width: 3, height: 14))
        arm.fillColor = SKColor(white: 0.3, alpha: 0.8); arm.strokeColor = .clear
        arm.position = CGPoint(x: p.x, y: p.y + 22); node.addChild(arm)
        board.addChild(icon())
        node.addChild(board)
    }

    private func addDoor(to node: SKNode, w: CGFloat, street: CGFloat, color: SKColor) {
        let door = SKShapeNode(rectOf: CGSize(width: 26, height: 40), cornerRadius: 12)
        door.fillColor = color; door.strokeColor = SKColor(white: 0, alpha: 0.25); door.lineWidth = 1.5
        door.position = CGPoint(x: 0, y: street + 22); door.zPosition = 1; node.addChild(door)
        let knob = SKShapeNode(circleOfRadius: 2.5)
        knob.fillColor = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1); knob.strokeColor = .clear
        knob.position = CGPoint(x: 7, y: street + 20); knob.zPosition = 1.1; node.addChild(knob)
    }

    private func addDoubleDoors(to node: SKNode, w: CGFloat, street: CGFloat) {
        for dx in [-15.0, 15.0] {
            let door = SKShapeNode(rectOf: CGSize(width: 26, height: 44), cornerRadius: 6)
            door.fillColor = SKColor(red: 0.40, green: 0.55, blue: 0.70, alpha: 1)
            door.strokeColor = SKColor(white: 0, alpha: 0.25); door.lineWidth = 1.5
            door.position = CGPoint(x: CGFloat(dx), y: street + 24); door.zPosition = 1; node.addChild(door)
        }
        let step = SKShapeNode(rectOf: CGSize(width: 78, height: 12), cornerRadius: 3)
        step.fillColor = SKColor(white: 0.78, alpha: 1); step.strokeColor = .clear
        step.position = CGPoint(x: 0, y: street + 2); node.addChild(step)
    }

    private func addClock(to node: SKNode, at p: CGPoint) {
        let face = SKShapeNode(circleOfRadius: 16)
        face.fillColor = .white; face.strokeColor = SKColor(red: 0.4, green: 0.3, blue: 0.22, alpha: 1)
        face.lineWidth = 3; face.position = p; face.zPosition = 2; node.addChild(face)
        for (dx, dy) in [(0.0, 9.0), (7.0, 0.0)] {     // two simple hands
            let hand = SKShapeNode(path: { let q = CGMutablePath(); q.move(to: .zero)
                q.addLine(to: CGPoint(x: dx, y: dy)); return q }())
            hand.strokeColor = SKColor(white: 0.15, alpha: 0.9); hand.lineWidth = 2.5
            hand.position = p; hand.zPosition = 2.1; node.addChild(hand)
        }
    }

    private func addFlag(to node: SKNode, at p: CGPoint) {
        let pole = SKShapeNode(rectOf: CGSize(width: 3, height: 56))
        pole.fillColor = SKColor(white: 0.55, alpha: 1); pole.strokeColor = .clear
        pole.position = p; pole.zPosition = 2; node.addChild(pole)
        let flag = SKShapeNode(rectOf: CGSize(width: 34, height: 22), cornerRadius: 2)
        flag.fillColor = SKColor(red: 0.90, green: 0.36, blue: 0.34, alpha: 1); flag.strokeColor = .clear
        flag.position = CGPoint(x: p.x + 18, y: p.y + 20); flag.zPosition = 2.1
        flag.run(.repeatForever(.sequence([                       // gentle wave
            .scaleX(to: 0.85, y: 1, duration: 0.7), .scaleX(to: 1, y: 1, duration: 0.7),
        ])))
        node.addChild(flag)
    }

    // --- wordless shop-sign icons (child-readable, nothing to translate) ---
    private func mugIcon() -> SKNode {
        let n = SKNode()
        let cup = SKShapeNode(rectOf: CGSize(width: 16, height: 14), cornerRadius: 3)
        cup.fillColor = SKColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1); cup.strokeColor = .clear
        cup.position = CGPoint(x: -2, y: -2); n.addChild(cup)
        let handle = SKShapeNode(circleOfRadius: 5)
        handle.fillColor = .clear; handle.strokeColor = SKColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1)
        handle.lineWidth = 3; handle.position = CGPoint(x: 8, y: -2); n.addChild(handle)
        let steam = SKShapeNode(rectOf: CGSize(width: 2.5, height: 8))
        steam.fillColor = SKColor(white: 0.6, alpha: 0.7); steam.strokeColor = .clear
        steam.position = CGPoint(x: -2, y: 10); n.addChild(steam)
        return n
    }
    private func bagIcon() -> SKNode {
        let n = SKNode()
        let bag = SKShapeNode(rectOf: CGSize(width: 16, height: 16), cornerRadius: 2)
        bag.fillColor = SKColor(red: 0.30, green: 0.62, blue: 0.58, alpha: 1); bag.strokeColor = .clear
        n.addChild(bag)
        let handle = SKShapeNode(circleOfRadius: 5)
        handle.fillColor = .clear; handle.strokeColor = SKColor(red: 0.30, green: 0.62, blue: 0.58, alpha: 1)
        handle.lineWidth = 2.5; handle.position = CGPoint(x: 0, y: 9); n.addChild(handle)
        return n
    }
    private func bellIcon() -> SKNode {
        let n = SKNode()
        let bell = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -8, y: -6)); p.addQuadCurve(to: CGPoint(x: 8, y: -6),
                control: CGPoint(x: 0, y: 12)); p.closeSubpath(); return p
        }())
        bell.fillColor = SKColor(red: 0.95, green: 0.78, blue: 0.30, alpha: 1); bell.strokeColor = .clear
        n.addChild(bell)
        let clap = SKShapeNode(circleOfRadius: 2.5)
        clap.fillColor = SKColor(red: 0.6, green: 0.45, blue: 0.15, alpha: 1); clap.strokeColor = .clear
        clap.position = CGPoint(x: 0, y: -7); n.addChild(clap)
        return n
    }
    private func bookIcon() -> SKNode {
        let n = SKNode()
        for sx in [-1.0, 1.0] {     // two pages of an open book
            let page = SKShapeNode(rectOf: CGSize(width: 13, height: 16), cornerRadius: 1)
            page.fillColor = sx < 0 ? SKColor(red: 0.55, green: 0.70, blue: 0.95, alpha: 1)
                                    : SKColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1)
            page.strokeColor = SKColor(white: 1, alpha: 0.8); page.lineWidth = 1
            page.zRotation = CGFloat(sx) * 0.12
            page.position = CGPoint(x: CGFloat(sx) * 7, y: 0); n.addChild(page)
        }
        return n
    }

    // Kenney art (CC0, Racing Pack) — see AmeliaTV/Assets/Kenney/. The hero bus
    // and the oblique buildings stay hand-drawn; traffic, people, and trees use
    // these sprites. Asset ids live in `ArtCatalog`.
    private let kenneyCharacters = ArtCatalog.people

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

    /// A Kenney top-down vehicle. The art faces "up", so the sprite is turned to
    /// point along +x; the container is what the scene rotates to the heading.
    private func makeKenneyCar(_ name: String, height: CGFloat = 96) -> SKNode {
        let node = SKNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: height * 1.04, height: height * 0.56))
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -5); node.addChild(shadow)
        let car = kenneySprite(name, height: height)
        car.zRotation = -.pi / 2
        node.addChild(car)
        return node
    }

    /// Parked cars lining the park-adjacent streets the bus does NOT drive (the
    /// cross-street stubs + ring approaches that poke up to the loop). The follow
    /// camera always has a lived-in street, and nothing ever sits in the bus's
    /// path. Deterministic (no RNG) so CI captures stay comparable. Decorative —
    /// no collision.
    private func buildParkedCars() {
        let corners = RoadNetwork.wellesCorners
        func isPerimeter(_ s: RoadSegment) -> Bool {
            corners.contains(where: { $0.distance(to: s.a) < 1 }) &&
            corners.contains(where: { $0.distance(to: s.b) < 1 })
        }
        var n = 0
        for s in net.segments {
            if isPerimeter(s) { continue }                       // never park on the bus's loop
            let mid = (s.a + s.b) * 0.5
            guard abs(mid.x) < 1150, abs(mid.z) < 1150 else { continue }   // only near the park
            let d = s.b - s.a; let len = d.length
            guard len > 280 else { continue }
            let dir = Vec2(d.x / len, d.z / len)
            let perp = Vec2(-dir.z, dir.x)
            let curb = s.width / 2 - 16                           // parking lane just inside the curb
            let heading = atan2(d.z, d.x)
            var t = 130.0
            while t < len - 130 {                                // keep clear of the junctions at each end
                for side in [-1.0, 1.0] {
                    let pos = s.a + dir * t + perp * (curb * side)
                    let name: String
                    switch n % 7 {
                    case 6: name = ArtCatalog.motorcycle
                    case 3: name = ArtCatalog.smallCars[n % ArtCatalog.smallCars.count]
                    default: name = ArtCatalog.cars[n % ArtCatalog.cars.count]
                    }
                    let height: CGFloat = name == ArtCatalog.motorcycle ? 56
                        : ArtCatalog.smallCars.contains(name) ? 70 : 86
                    let node = makeKenneyCar(name, height: height)
                    node.position = pt(pos)
                    node.zRotation = -CGFloat(heading)
                    node.zPosition = 8
                    worldNode.addChild(node)
                    n += 1
                }
                t += 210
            }
        }
    }

    /// Amelia, the cute top-down hero bus: a plump rounded yellow body with a
    /// soft top highlight, a windshield + nose bumper and warm headlights at the
    /// front (+x), and a friendly face — big bright eyes with catchlights, a happy
    /// smile, and rosy cheeks. Original design (D-IP-1).
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
        // rounder, friendlier body with a soft top highlight + bottom shade so it
        // reads as a plump 3D pill from above.
        let body = SKShapeNode(rectOf: CGSize(width: length, height: width), cornerRadius: 30)
        body.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1)
        body.strokeColor = SKColor(red: 0.82, green: 0.52, blue: 0.08, alpha: 1); body.lineWidth = 3
        node.addChild(body)
        let topHi = SKShapeNode(rectOf: CGSize(width: length * 0.9, height: width * 0.46), cornerRadius: 22)
        topHi.fillColor = SKColor(white: 1, alpha: 0.12); topHi.strokeColor = .clear
        topHi.position = CGPoint(x: 0, y: width * 0.22); node.addChild(topHi)
        let botSh = SKShapeNode(rectOf: CGSize(width: length * 0.92, height: width * 0.34), cornerRadius: 16)
        botSh.fillColor = SKColor(white: 0, alpha: 0.10); botSh.strokeColor = .clear
        botSh.position = CGPoint(x: 0, y: -width * 0.27); node.addChild(botSh)

        // rear roof window + a little roof hatch, so the back half isn't bare
        let rearWin = SKShapeNode(rectOf: CGSize(width: length * 0.16, height: width * 0.52), cornerRadius: 6)
        rearWin.fillColor = SKColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1)
        rearWin.strokeColor = SKColor(white: 0, alpha: 0.18); rearWin.lineWidth = 1.5
        rearWin.position = CGPoint(x: -length * 0.30, y: 0); node.addChild(rearWin)
        let hatch = SKShapeNode(rectOf: CGSize(width: length * 0.12, height: width * 0.34), cornerRadius: 4)
        hatch.fillColor = SKColor(red: 0.96, green: 0.74, blue: 0.16, alpha: 1)
        hatch.strokeColor = SKColor(white: 0, alpha: 0.18); hatch.lineWidth = 1
        hatch.position = CGPoint(x: -length * 0.08, y: 0); node.addChild(hatch)

        // big curved windshield at the front (+x) — the face lives on it
        let windshield = SKShapeNode(rectOf: CGSize(width: length * 0.26, height: width * 0.64), cornerRadius: 14)
        windshield.fillColor = SKColor(red: 0.74, green: 0.89, blue: 0.99, alpha: 1)
        windshield.strokeColor = SKColor(white: 0, alpha: 0.18); windshield.lineWidth = 1.5
        windshield.position = CGPoint(x: length * 0.22, y: 0); node.addChild(windshield)

        // a dark front bumper + two warm headlights at the nose
        let bumper = SKShapeNode(rectOf: CGSize(width: length * 0.05, height: width * 0.82), cornerRadius: 4)
        bumper.fillColor = SKColor(white: 0.18, alpha: 1); bumper.strokeColor = .clear
        bumper.position = CGPoint(x: length * 0.49, y: 0); node.addChild(bumper)
        for sy in [-width * 0.30, width * 0.30] {
            let lamp = SKShapeNode(rectOf: CGSize(width: length * 0.05, height: width * 0.16), cornerRadius: 3)
            lamp.fillColor = SKColor(red: 1.0, green: 0.96, blue: 0.74, alpha: 1)
            lamp.strokeColor = SKColor(white: 0, alpha: 0.2); lamp.lineWidth = 1
            lamp.position = CGPoint(x: length * 0.45, y: sy); node.addChild(lamp)
        }

        // big bright eyes (with catchlights) looking ahead + a happy smile + cheeks
        for sy in [-width * 0.20, width * 0.20] {
            let eyeWhite = SKShapeNode(circleOfRadius: width * 0.19)
            eyeWhite.fillColor = .white; eyeWhite.strokeColor = SKColor(white: 0, alpha: 0.14); eyeWhite.lineWidth = 1
            eyeWhite.position = CGPoint(x: length * 0.24, y: sy); node.addChild(eyeWhite)
            let pupil = SKShapeNode(circleOfRadius: width * 0.10)
            pupil.fillColor = SKColor(white: 0.08, alpha: 1); pupil.strokeColor = .clear
            pupil.position = CGPoint(x: length * 0.28, y: sy); node.addChild(pupil)
            let glint = SKShapeNode(circleOfRadius: width * 0.035)
            glint.fillColor = .white; glint.strokeColor = .clear
            glint.position = CGPoint(x: length * 0.30, y: sy + width * 0.05); node.addChild(glint)
        }
        let smile = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: length * 0.40, y: -width * 0.12))
            p.addQuadCurve(to: CGPoint(x: length * 0.40, y: width * 0.12),
                           control: CGPoint(x: length * 0.47, y: 0))
            return p
        }())
        smile.strokeColor = SKColor(red: 0.45, green: 0.26, blue: 0.16, alpha: 0.9)
        smile.lineWidth = 3; smile.lineCap = .round; smile.fillColor = .clear
        node.addChild(smile)
        for sy in [-width * 0.36, width * 0.36] {
            let cheek = SKShapeNode(circleOfRadius: width * 0.085)
            cheek.fillColor = SKColor(red: 1.0, green: 0.56, blue: 0.56, alpha: 0.85); cheek.strokeColor = .clear
            cheek.position = CGPoint(x: length * 0.36, y: sy); node.addChild(cheek)
        }
        return node
    }

    /// Roadside trees — mostly ringing the map to fill the empty grass the follow
    /// camera shows at the edges, plus a few inside the blocks for life.
    private func buildTrees() {
        // Parkway trees lining both sides of every avenue (the "sidewalk + grass +
        // trees" look), skipping any that would land on a road or a building.
        // Line the streets near the park (skip the far outer-ring streets — they're
        // never on camera and the trees there only slow the build).
        for s in net.segments {
            let mid = (s.a + s.b) * 0.5
            if abs(mid.x) < 1150, abs(mid.z) < 1150 { lineWithTrees(s.a, s.b, width: s.width) }
        }
        // A few specimen trees in open interior spots.
        for v in [Vec2(-150, 250), Vec2(120, 150), Vec2(-600, 200)] { worldNode.addChild(tree(at: v)) }
    }

    /// Plant trees at intervals along both sides of a road segment, just beyond the
    /// curb, skipping spots that overlap another road or a building footprint.
    private func lineWithTrees(_ a: Vec2, _ b: Vec2, width: Double) {
        let d = b - a; let len = d.length
        guard len > 1 else { return }
        let dir = Vec2(d.x / len, d.z / len)
        let perp = Vec2(-dir.z, dir.x)
        let off = width / 2 + parkwayWidth / 2 + 4   // in the grassy parkway, between curb and sidewalk
        let step = 200.0
        // keep trees clear of the bus stop and the Quick-Stop crossing
        let reserved = [Vec2(-200, -600), challengePoint, Vec2(40, -805), Vec2(100, -800)]
        var t = step / 2
        while t < len {
            let base = a + dir * t
            for side in [-1.0, 1.0] {
                let v = base + perp * (off * side)
                if net.distanceToRoad(v) > 42, !nearBuilding(v),
                   reserved.allSatisfy({ $0.distance(to: v) > 120 }) {
                    worldNode.addChild(tree(at: v))
                }
            }
            t += step
        }
    }

    /// True if `v` lands on (or right next to) a building footprint or the library.
    private func nearBuilding(_ v: Vec2) -> Bool {
        for f in placedFootprints
        where abs(v.x - f.c.x) < f.hw + 30 && abs(v.z - f.c.z) < f.hd + 30 { return true }
        if abs(v.x - perspCenter.x) < Double(perspSize.width) / 2 + 40,
           abs(v.z - perspCenter.z) < Double(perspSize.height) / 2 + 40 { return true }
        return false
    }

    private func tree(at v: Vec2) -> SKNode {
        let node = SKNode(); node.position = pt(v); node.zPosition = 6
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 58, height: 30))
        shadow.fillColor = SKColor(white: 0, alpha: 0.15); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 4, y: -22); node.addChild(shadow)
        node.addChild(kenneySprite(ArtCatalog.treeLarge, height: 66))
        return node
    }

    /// Cozy static dressing: a little park (pond + benches) in the open grass
    /// below the loop, a bus stop beside the road, and flower clusters scattered
    /// about. All off the roads so nothing blocks driving.
    private func buildScenery() {
        addParkSidewalk()                  // the paved walk up the middle of the park
        buildPark()
        addChurch(at: Vec2(-260, -945))    // on the north frontage, left of the road's middle
        addBusStop(at: Vec2(-200, -600))   // on the Montrose curb, inside the park
        for f in [Vec2(-560, -430), Vec2(-150, 470), Vec2(60, 560), Vec2(-300, 130), Vec2(120, -250)] {
            addFlowers(at: f)
        }
    }

    /// Welles Park, laid out to spec: a central walk with a gazebo to its left; the
    /// indoor pool + gymnasium just inside the north road (centre-west); the tennis
    /// courts in the centre; TWO big ball fields tucked into the east corners (NE +
    /// SE), each turned to face the park centre; a wooded southwest with a winding
    /// path; and a large playground (two swing sets, a play structure, a splash pad).
    /// The park life — runners, dogs, families — is filled in by `buildPeds`.
    private func buildPark() {
        addPlayground(center: Vec2(-540, -90))                   // fenced, on the west by Western
        addPool(center: Vec2(-80, -330))                         // the fieldhouse pool, north-centre
        addGym(center: Vec2(-80, -90))                           // the gym, stacked just south of it
        addGazebo(at: Vec2(-250, 150))
        addCourts(center: Vec2(120, 80))                         // the tennis/sport courts, centre
        // TWO big ball diamonds, one tucked in each east corner (NE + SE), each
        // turned so the pitcher throws toward the park centre — home plate on the
        // inside, the outfield fanning out into the corner. Sized large, and kept
        // clear of the roads, the courts, and the fieldhouse.
        let parkCenter = Vec2(-30, 0)
        addBaseballField(center: Vec2(300, -350), radius: 175, facing: parkCenter)   // NE corner
        addBaseballField(center: Vec2(370, 355), radius: 175, facing: parkCenter)    // SE corner
        addWoods(center: Vec2(-540, 430))                        // SW trees, path joins the central walk
        addYieldSign(at: Vec2(-260, 120))                        // where the adventure path meets the walk
        for p in [Vec2(-340, -360), Vec2(-360, 320), Vec2(60, 470)] { addShadeTree(at: p) }
    }

    /// The paved walk up the middle of the park. It meets the north and south roads
    /// (so it connects to the sidewalks) and *winds left* around the central
    /// buildings on its way down. The wooded southwest path joins it (see addWoods).
    private let centerWalkControls = (
        top: Vec2(-40, -652), c1: Vec2(-300, -360), c2: Vec2(-300, 60),
        mid: Vec2(-120, 200), c3: Vec2(20, 360), c4: Vec2(-40, 560), bottom: Vec2(-40, 652)
    )
    private func addParkSidewalk() {
        let w = centerWalkControls
        let path = CGMutablePath()
        path.move(to: pt(w.top))
        path.addCurve(to: pt(w.mid), control1: pt(w.c1), control2: pt(w.c2))   // bow west around the buildings
        path.addCurve(to: pt(w.bottom), control1: pt(w.c3), control2: pt(w.c4))
        let walk = SKShapeNode(path: path)
        walk.strokeColor = SKColor(red: 0.85, green: 0.83, blue: 0.77, alpha: 1)
        walk.lineWidth = 30; walk.lineCap = .round; walk.fillColor = .clear; walk.zPosition = 1.4
        worldNode.addChild(walk)
        let seam = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: [14, 16]))
        seam.strokeColor = SKColor(white: 0.7, alpha: 0.4); seam.lineWidth = 1.5; seam.fillColor = .clear
        seam.zPosition = 1.45; worldNode.addChild(seam)
        addBench(at: Vec2(-220, -120)); addBench(at: Vec2(-80, 240))
    }

    private func polygonPath(sides: Int, radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<sides {
            let a = CGFloat(i) / CGFloat(sides) * .pi * 2 + .pi / CGFloat(sides)
            let v = CGPoint(x: cos(a) * radius, y: sin(a) * radius)
            if i == 0 { p.move(to: v) } else { p.addLine(to: v) }
        }
        p.closeSubpath(); return p
    }

    /// A proper park gazebo: a big round deck ringed with posts under an eight-sided
    /// roof with a finial — large enough to read clearly from the wide shot.
    private func addGazebo(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 5
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 210, height: 110))
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 8, y: -44); node.addChild(shadow)
        let deck = SKShapeNode(circleOfRadius: 86)
        deck.fillColor = SKColor(red: 0.82, green: 0.72, blue: 0.55, alpha: 1)
        deck.strokeColor = SKColor(white: 0, alpha: 0.2); deck.lineWidth = 3; node.addChild(deck)
        let step = SKShapeNode(circleOfRadius: 96)
        step.fillColor = .clear; step.strokeColor = SKColor(red: 0.70, green: 0.60, blue: 0.45, alpha: 0.7)
        step.lineWidth = 3; node.addChild(step)
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * .pi * 2
            let post = SKShapeNode(circleOfRadius: 6)
            post.fillColor = SKColor(white: 0.96, alpha: 1); post.strokeColor = .clear
            post.position = CGPoint(x: cos(a) * 80, y: sin(a) * 80); node.addChild(post)
        }
        let roof = SKShapeNode(path: polygonPath(sides: 8, radius: 104))
        roof.fillColor = SKColor(red: 0.50, green: 0.36, blue: 0.30, alpha: 1)
        roof.strokeColor = SKColor(white: 0, alpha: 0.25); roof.lineWidth = 3
        roof.position = CGPoint(x: 0, y: 44); node.addChild(roof)
        let roofHi = SKShapeNode(path: polygonPath(sides: 8, radius: 52))
        roofHi.fillColor = SKColor(red: 0.58, green: 0.43, blue: 0.36, alpha: 1); roofHi.strokeColor = .clear
        roofHi.position = CGPoint(x: 0, y: 44); node.addChild(roofHi)
        let finial = SKShapeNode(circleOfRadius: 9)
        finial.fillColor = SKColor(red: 0.92, green: 0.80, blue: 0.42, alpha: 1); finial.strokeColor = .clear
        finial.position = CGPoint(x: 0, y: 100); node.addChild(finial)
        worldNode.addChild(node)
    }

    /// A yield sign: a downward-pointing white triangle with a red border on a post.
    private func addYieldSign(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 7
        let post = SKShapeNode(rectOf: CGSize(width: 4, height: 24))
        post.fillColor = SKColor(white: 0.5, alpha: 1); post.strokeColor = .clear
        post.position = CGPoint(x: 0, y: -14); node.addChild(post)
        let tri = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -15, y: 13)); p.addLine(to: CGPoint(x: 15, y: 13))
            p.addLine(to: CGPoint(x: 0, y: -13)); p.closeSubpath(); return p
        }())
        tri.fillColor = SKColor(red: 0.86, green: 0.20, blue: 0.20, alpha: 1)
        tri.strokeColor = .white; tri.lineWidth = 3; node.addChild(tri)
        let inner = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -8, y: 7)); p.addLine(to: CGPoint(x: 8, y: 7))
            p.addLine(to: CGPoint(x: 0, y: -6)); p.closeSubpath(); return p
        }())
        inner.fillColor = .white; inner.strokeColor = .clear; node.addChild(inner)
        worldNode.addChild(node)
    }

    /// A faked-height park building (pool / gym share this): brick body + roof + a
    /// warm-lit window band; `front` draws the kind-specific detail on the roof face.
    private func addParkBuilding(center: Vec2, wWorld: CGFloat, dWorld: CGFloat, h: CGFloat,
                                 wall: SKColor, roof rc: SKColor,
                                 front: (SKNode, CGFloat, CGFloat, CGFloat) -> Void) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 5
        let w = wWorld * scale, d = dWorld * scale
        let shadow = SKShapeNode(rectOf: CGSize(width: w + 12, height: d + h + 12), cornerRadius: 8)
        shadow.fillColor = SKColor(white: 0, alpha: 0.16); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 10, y: h / 2 - 10); node.addChild(shadow)
        let body = SKShapeNode(rectOf: CGSize(width: w, height: d + h), cornerRadius: 7)
        body.fillColor = wall; body.strokeColor = SKColor(white: 0, alpha: 0.2); body.lineWidth = 2
        body.position = CGPoint(x: 0, y: h / 2); node.addChild(body)
        let cols = max(3, Int(w / 80))
        for c in 0..<cols {
            let win = SKShapeNode(rectOf: CGSize(width: w / CGFloat(cols) * 0.5, height: 22), cornerRadius: 3)
            win.fillColor = c % 3 == 0 ? SKColor(red: 1, green: 0.86, blue: 0.46, alpha: 1)
                                       : SKColor(red: 0.66, green: 0.82, blue: 0.95, alpha: 1)
            win.strokeColor = SKColor(white: 0.2, alpha: 0.3); win.lineWidth = 1
            win.position = CGPoint(x: -w / 2 + (CGFloat(c) + 0.5) * (w / CGFloat(cols)), y: -d / 2 + h * 0.5)
            node.addChild(win)
        }
        let roof = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 7)
        roof.fillColor = rc; roof.strokeColor = SKColor(white: 0, alpha: 0.18); roof.lineWidth = 2
        roof.position = CGPoint(x: 0, y: h); node.addChild(roof)
        front(node, w, d, h)
        worldNode.addChild(node)
    }

    /// The indoor pool: a glass-roofed hall revealing a big lane pool, plus a side
    /// wing standing in for the "rooms you can't see".
    private func addPool(center: Vec2) {
        addParkBuilding(center: center, wWorld: 220, dWorld: 150, h: 64,
                        wall: SKColor(red: 0.62, green: 0.72, blue: 0.80, alpha: 1),
                        roof: SKColor(red: 0.74, green: 0.82, blue: 0.88, alpha: 1)) { node, w, d, h in
            let pool = SKShapeNode(rectOf: CGSize(width: w * 0.6, height: d * 0.58), cornerRadius: 8)
            pool.fillColor = SKColor(red: 0.30, green: 0.66, blue: 0.92, alpha: 1)
            pool.strokeColor = SKColor(white: 1, alpha: 0.6); pool.lineWidth = 3
            pool.position = CGPoint(x: -w * 0.12, y: h); node.addChild(pool)
            for k in -1...1 {
                let lane = SKShapeNode(rectOf: CGSize(width: w * 0.58, height: 2))
                lane.fillColor = SKColor(white: 1, alpha: 0.6); lane.strokeColor = .clear
                lane.position = CGPoint(x: -w * 0.12, y: h + CGFloat(k) * d * 0.16); node.addChild(lane)
            }
            let wing = SKShapeNode(rectOf: CGSize(width: w * 0.24, height: d * 0.72), cornerRadius: 6)
            wing.fillColor = SKColor(red: 0.56, green: 0.66, blue: 0.74, alpha: 1)
            wing.strokeColor = SKColor(white: 0, alpha: 0.15); wing.lineWidth = 1
            wing.position = CGPoint(x: w * 0.34, y: h); node.addChild(wing)
            // Swimmers do laps ALONG the lanes (the lanes run left–right, so they
            // swim left–right too), one per lane, staggered so they don't line up.
            for k in -1...1 {
                self.addSwimmer(to: node, at: CGPoint(x: -w * 0.12, y: h + CGFloat(k) * d * 0.16),
                                span: w * 0.46, phase: Double(k + 1) * 0.8)
            }
            self.addSign(to: node, at: CGPoint(x: -w * 0.34, y: 30)) { self.waterDropIcon() }
        }
    }

    /// The gymnasium: a brick hall with a wood-toned indoor court on the roof face.
    private func addGym(center: Vec2) {
        addParkBuilding(center: center, wWorld: 240, dWorld: 150, h: 70,
                        wall: SKColor(red: 0.72, green: 0.52, blue: 0.40, alpha: 1),
                        roof: SKColor(red: 0.85, green: 0.68, blue: 0.46, alpha: 1)) { node, w, d, h in
            let court = SKShapeNode(rectOf: CGSize(width: w * 0.62, height: d * 0.5), cornerRadius: 4)
            court.fillColor = SKColor(red: 0.80, green: 0.60, blue: 0.38, alpha: 1)
            court.strokeColor = SKColor(white: 1, alpha: 0.7); court.lineWidth = 2
            court.position = CGPoint(x: 0, y: h); node.addChild(court)
            let circ = SKShapeNode(circleOfRadius: d * 0.12)
            circ.fillColor = .clear; circ.strokeColor = SKColor(white: 1, alpha: 0.7); circ.lineWidth = 2
            circ.position = CGPoint(x: 0, y: h); node.addChild(circ)
            self.addSign(to: node, at: CGPoint(x: w * 0.34, y: 30)) { self.bballIcon() }
        }
    }

    private func waterDropIcon() -> SKNode {
        let n = SKNode()
        let drop = SKShapeNode(circleOfRadius: 9)
        drop.fillColor = SKColor(red: 0.30, green: 0.66, blue: 0.92, alpha: 1); drop.strokeColor = .clear
        drop.position = CGPoint(x: 0, y: -3); n.addChild(drop)
        let tip = SKShapeNode(path: { let p = CGMutablePath()
            p.move(to: CGPoint(x: -6, y: 2)); p.addLine(to: CGPoint(x: 6, y: 2))
            p.addLine(to: CGPoint(x: 0, y: 13)); p.closeSubpath(); return p }())
        tip.fillColor = drop.fillColor; tip.strokeColor = .clear; n.addChild(tip)
        return n
    }
    private func bballIcon() -> SKNode {
        let n = SKNode()
        let ball = SKShapeNode(circleOfRadius: 9)
        ball.fillColor = SKColor(red: 0.90, green: 0.50, blue: 0.25, alpha: 1)
        ball.strokeColor = SKColor(white: 0.2, alpha: 0.6); ball.lineWidth = 1.5; n.addChild(ball)
        let s1 = SKShapeNode(rectOf: CGSize(width: 18, height: 1.5))
        s1.fillColor = SKColor(white: 0.2, alpha: 0.6); s1.strokeColor = .clear; n.addChild(s1)
        let s2 = SKShapeNode(rectOf: CGSize(width: 1.5, height: 18))
        s2.fillColor = SKColor(white: 0.2, alpha: 0.6); s2.strokeColor = .clear; n.addChild(s2)
        return n
    }

    /// A big ball field: a mowed green circle, a dirt infield fan at the bottom with
    /// bases + a pitcher's mound, and an outfield FENCE arcing along the top (behind
    /// the mound). Sized in world units so it reads properly large. The whole field
    /// is turned so home→pitcher points at `facing` (the park centre) — the pitcher
    /// faces the centre, the outfield fans into the corner — and it's filled with a
    /// full team actually playing ball (a pitch loops from the mound to the plate).
    private func addBaseballField(center: Vec2, radius: Double, facing target: Vec2) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 4
        // Screen-space direction from the field toward the park centre. The field is
        // authored with home plate at the bottom (local -y); rotate so that local -y
        // lands on this direction, i.e. the pitcher throws toward the centre.
        let toC = CGVector(dx: CGFloat(target.x - center.x), dy: -CGFloat(target.z - center.z))
        let clen = max(0.0001, (toC.dx * toC.dx + toC.dy * toC.dy).squareRoot())
        let f = CGVector(dx: toC.dx / clen, dy: toC.dy / clen)
        let theta = atan2(f.dx, -f.dy)            // rotation mapping local (0,-1) → f
        node.zRotation = theta
        let R = CGFloat(radius) * scale
        let grass = SKShapeNode(circleOfRadius: R)
        grass.fillColor = SKColor(red: 0.42, green: 0.70, blue: 0.42, alpha: 1)
        grass.strokeColor = SKColor(white: 1, alpha: 0.15); grass.lineWidth = 2; node.addChild(grass)
        let home = CGPoint(x: 0, y: -R * 0.5)
        let dirt = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath(); p.move(to: home)
            p.addArc(center: home, radius: R * 0.78, startAngle: .pi * 0.16, endAngle: .pi * 0.84, clockwise: false)
            p.closeSubpath(); return p
        }())
        dirt.fillColor = SKColor(red: 0.80, green: 0.62, blue: 0.42, alpha: 1); dirt.strokeColor = .clear
        node.addChild(dirt)
        // diamond: home, first (right), second (top), third (left)
        let first = CGPoint(x: R * 0.34, y: home.y + R * 0.34)
        let third = CGPoint(x: -R * 0.34, y: home.y + R * 0.34)
        let second = CGPoint(x: 0, y: home.y + R * 0.68)
        let diamond = CGMutablePath()
        diamond.move(to: home); diamond.addLine(to: first)
        diamond.addLine(to: second); diamond.addLine(to: third); diamond.closeSubpath()
        let lines = SKShapeNode(path: diamond)
        lines.strokeColor = SKColor(white: 1, alpha: 0.85); lines.lineWidth = 3
        lines.fillColor = SKColor(red: 0.46, green: 0.74, blue: 0.46, alpha: 1); node.addChild(lines)
        for b in [home, first, second, third] {
            let base = SKShapeNode(rectOf: CGSize(width: 11, height: 11), cornerRadius: 2)
            base.fillColor = .white; base.strokeColor = .clear; base.position = b; node.addChild(base)
        }
        let mound = SKShapeNode(circleOfRadius: R * 0.05)
        mound.fillColor = SKColor(red: 0.74, green: 0.56, blue: 0.38, alpha: 1); mound.strokeColor = .clear
        mound.position = CGPoint(x: 0, y: home.y + R * 0.34); node.addChild(mound)
        // outfield fence arc along the top (behind the mound) — posts + a rail
        let fenceR = R * 0.92
        let rail = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.addArc(center: .zero, radius: fenceR, startAngle: .pi * 0.12, endAngle: .pi * 0.88, clockwise: false)
            return p
        }())
        rail.strokeColor = SKColor(white: 0.95, alpha: 0.85); rail.lineWidth = 3; rail.fillColor = .clear
        node.addChild(rail)
        var deg = 22.0
        while deg <= 158.0 {
            let a = CGFloat(deg) * .pi / 180
            let post = SKShapeNode(circleOfRadius: 3.5)
            post.fillColor = SKColor(white: 0.95, alpha: 0.95); post.strokeColor = .clear
            post.position = CGPoint(x: cos(a) * fenceR, y: sin(a) * fenceR); node.addChild(post)
            deg += 9.0
        }
        addBaseballPlayers(to: node, R: R, home: home, theta: theta)
        worldNode.addChild(node)
    }

    /// Fill a (rotated) ball field with a full team actually playing: a batter and
    /// catcher at the plate, the pitcher on the mound, infielders on the bases, and
    /// three outfielders — plus a ball that loops mound → plate → a hit to the
    /// outfield. Players are children of the rotated field but counter-rotated by
    /// `-theta` so they stay upright.
    private func addBaseballPlayers(to node: SKNode, R: CGFloat, home: CGPoint, theta: CGFloat) {
        func player(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat = 24) {
            let p = makePersonNode(height: h)
            p.position = CGPoint(x: x, y: y); p.zRotation = -theta; p.zPosition = 5
            p.run(.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 0.5),
                                            .moveBy(x: 0, y: -2, duration: 0.5)])))
            node.addChild(p)
        }
        player(R * 0.10, home.y)                 // batter, at the plate
        player(0, home.y - R * 0.12, 21)         // catcher, behind the plate
        player(0, home.y + R * 0.34)             // pitcher, on the mound
        player(R * 0.34, home.y + R * 0.34)      // first base
        player(-R * 0.34, home.y + R * 0.34)     // third base
        player(0, home.y + R * 0.68)             // second base
        player(-R * 0.20, home.y + R * 0.52)     // shortstop
        player(R * 0.5, R * 0.46)                // right field
        player(-R * 0.5, R * 0.46)               // left field
        player(0, R * 0.64)                      // center field
        let mound = CGPoint(x: 0, y: home.y + R * 0.34)
        let ball = SKShapeNode(circleOfRadius: 4)
        ball.fillColor = .white; ball.strokeColor = SKColor(white: 0, alpha: 0.4); ball.lineWidth = 1
        ball.position = mound; ball.zPosition = 6; node.addChild(ball)
        ball.run(.repeatForever(.sequence([
            .move(to: home, duration: 0.55),                                 // the pitch
            .move(to: CGPoint(x: R * 0.4, y: R * 0.5), duration: 0.5),       // crack — a hit to right
            .move(to: mound, duration: 0.5),                                 // thrown back in
            .wait(forDuration: 0.4),
        ])))
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

    /// The courts cluster at the south-middle of the park: two blue tennis courts
    /// over two clay pickleball courts.
    private func addCourts(center: Vec2) {
        let blue = SKColor(red: 0.30, green: 0.52, blue: 0.66, alpha: 1)
        let clay = SKColor(red: 0.62, green: 0.40, blue: 0.34, alpha: 1)
        addCourt(at: center + Vec2(-100, -70), size: CGSize(width: 170, height: 88), surface: blue)
        addCourt(at: center + Vec2(100, -70), size: CGSize(width: 170, height: 88), surface: blue)
        addCourt(at: center + Vec2(-75, 80), size: CGSize(width: 130, height: 70), surface: clay)
        addCourt(at: center + Vec2(75, 80), size: CGSize(width: 130, height: 70), surface: clay)
    }

    /// A large playground: a soft pad with a play structure (tower + slide), TWO
    /// swing sets, a sandbox, and a fountain splash pad — the heart of the park.
    private func addPlayground(center: Vec2) {
        let node = SKNode(); node.position = pt(center); node.zPosition = 4
        let w = 360 * scale, d = 280 * scale
        let pad = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 26)
        pad.fillColor = SKColor(red: 0.88, green: 0.74, blue: 0.52, alpha: 1)
        pad.strokeColor = SKColor(white: 1, alpha: 0.22); pad.lineWidth = 2; node.addChild(pad)
        // a low fence around the playground, with a gap for the gate at the bottom
        addPlaygroundFence(to: node, w: w + 26, d: d + 26)
        // play structure: a platform tower with a peaked roof + a slide chute
        let tower = SKShapeNode(rectOf: CGSize(width: 72, height: 62), cornerRadius: 6)
        tower.fillColor = SKColor(red: 0.40, green: 0.62, blue: 0.55, alpha: 1); tower.strokeColor = .clear
        tower.position = CGPoint(x: -w * 0.30, y: d * 0.12); node.addChild(tower)
        let towerRoof = SKShapeNode(path: polygonPath(sides: 3, radius: 48))
        towerRoof.fillColor = SKColor(red: 0.90, green: 0.40, blue: 0.40, alpha: 1); towerRoof.strokeColor = .clear
        towerRoof.zRotation = .pi / 2; towerRoof.position = CGPoint(x: -w * 0.30, y: d * 0.12 + 46); node.addChild(towerRoof)
        let chute = SKShapeNode(rectOf: CGSize(width: 20, height: 92), cornerRadius: 8)
        chute.fillColor = SKColor(red: 0.95, green: 0.72, blue: 0.30, alpha: 1); chute.strokeColor = .clear
        chute.zRotation = 0.6; chute.position = CGPoint(x: -w * 0.30 + 64, y: d * 0.02); node.addChild(chute)
        // two swing sets => "swings ... and more swings"
        addSwingSet(to: node, at: CGPoint(x: w * 0.16, y: d * 0.26))
        addSwingSet(to: node, at: CGPoint(x: w * 0.16, y: -d * 0.18))
        // sandbox
        let sand = SKShapeNode(rectOf: CGSize(width: 84, height: 60), cornerRadius: 8)
        sand.fillColor = SKColor(red: 0.93, green: 0.84, blue: 0.58, alpha: 1)
        sand.strokeColor = SKColor(red: 0.70, green: 0.50, blue: 0.30, alpha: 1); sand.lineWidth = 3
        sand.position = CGPoint(x: -w * 0.32, y: -d * 0.28); node.addChild(sand)
        worldNode.addChild(node)
        addSplashpad(at: center + Vec2(120, 10))
        for off in [Vec2(-150, 40), Vec2(110, 90), Vec2(60, -60), Vec2(-60, 110), Vec2(170, -40)] {
            addKid(at: center + off)
        }
    }

    /// A low picket fence around the playground rim, with a gate gap at the bottom.
    private func addPlaygroundFence(to node: SKNode, w: CGFloat, d: CGFloat) {
        let rail = SKShapeNode(rectOf: CGSize(width: w, height: d), cornerRadius: 10)
        rail.fillColor = .clear; rail.strokeColor = SKColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 0.95)
        rail.lineWidth = 4; rail.zPosition = 0.1; node.addChild(rail)
        let step = 34.0
        func post(_ x: CGFloat, _ y: CGFloat) {
            let p = SKShapeNode(circleOfRadius: 3.5)
            p.fillColor = SKColor(white: 0.97, alpha: 1); p.strokeColor = .clear
            p.position = CGPoint(x: x, y: y); p.zPosition = 0.12; node.addChild(p)
        }
        var x = -w / 2
        while x <= w / 2 {
            if abs(x) > 36 { post(x, d / 2) }          // top rail posts
            post(x, -d / 2)                            // bottom rail posts (gate gap left open by pad)
            x += step
        }
        var y = -d / 2
        while y <= d / 2 { post(-w / 2, y); post(w / 2, y); y += step }
        // gate posts marking the entrance at the bottom-centre
        post(-36, d / 2); post(36, d / 2)
    }

    private func addSwingSet(to node: SKNode, at p: CGPoint) {
        let beam = SKShapeNode(rectOf: CGSize(width: 86, height: 7), cornerRadius: 3)
        beam.fillColor = SKColor(red: 0.40, green: 0.55, blue: 0.70, alpha: 1); beam.strokeColor = .clear
        beam.position = CGPoint(x: p.x, y: p.y + 30); node.addChild(beam)
        for dx in [-28.0, 0.0, 28.0] {
            let rope = SKShapeNode(rectOf: CGSize(width: 2.5, height: 40))
            rope.fillColor = SKColor(white: 0.3, alpha: 0.8); rope.strokeColor = .clear
            rope.position = CGPoint(x: p.x + CGFloat(dx), y: p.y + 8); node.addChild(rope)
            let seat = SKShapeNode(rectOf: CGSize(width: 16, height: 5), cornerRadius: 2)
            seat.fillColor = SKColor(red: 0.30, green: 0.55, blue: 0.40, alpha: 1); seat.strokeColor = .clear
            seat.position = CGPoint(x: p.x + CGFloat(dx), y: p.y - 12); node.addChild(seat)
        }
    }

    /// A fountain splash pad: a wet circular pad with little water jets that pulse.
    private func addSplashpad(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 3.6
        let pad = SKShapeNode(circleOfRadius: 72)
        pad.fillColor = SKColor(red: 0.58, green: 0.78, blue: 0.86, alpha: 1)
        pad.strokeColor = SKColor(white: 1, alpha: 0.4); pad.lineWidth = 2; node.addChild(pad)
        let wet = SKShapeNode(circleOfRadius: 46)
        wet.fillColor = SKColor(red: 0.42, green: 0.70, blue: 0.90, alpha: 0.5); wet.strokeColor = .clear
        node.addChild(wet)
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * .pi * 2
            let jet = SKShapeNode(rectOf: CGSize(width: 5, height: 26), cornerRadius: 2.5)
            jet.fillColor = SKColor(white: 1, alpha: 0.8); jet.strokeColor = .clear
            jet.position = CGPoint(x: cos(a) * 32, y: sin(a) * 32); jet.yScale = 0.3
            jet.run(.repeatForever(.sequence([
                .scaleY(to: 1.0, duration: 0.4 + Double(i) * 0.05),
                .scaleY(to: 0.3, duration: 0.4), .wait(forDuration: 0.2),
            ])))
            node.addChild(jet)
        }
        let jetC = SKShapeNode(rectOf: CGSize(width: 6, height: 34), cornerRadius: 3)
        jetC.fillColor = SKColor(white: 1, alpha: 0.85); jetC.strokeColor = .clear
        jetC.run(.repeatForever(.sequence([.scaleY(to: 1.3, duration: 0.5), .scaleY(to: 0.7, duration: 0.5)])))
        node.addChild(jetC)
        worldNode.addChild(node)
    }

    /// The wooded southwest of the park: a grove of shade trees threaded by a dirt
    /// "adventure" path that winds up to **join the central walk** (so the paths
    /// connect, as on the real map). Flower clumps fill the grass between.
    private func addWoods(center: Vec2) {
        let join = Vec2(-280, 90)         // meets the central walk on its western bow
        let path = CGMutablePath()
        path.move(to: pt(center + Vec2(-120, 180)))
        path.addQuadCurve(to: pt(center + Vec2(60, 10)), control: pt(center + Vec2(-60, 110)))
        path.addQuadCurve(to: pt(join), control: pt(center + Vec2(230, -180)))
        let walk = SKShapeNode(path: path)
        walk.strokeColor = SKColor(red: 0.78, green: 0.70, blue: 0.55, alpha: 1)
        walk.lineWidth = 18; walk.lineCap = .round; walk.fillColor = .clear; walk.zPosition = 1.3
        worldNode.addChild(walk)
        let spots: [Vec2] = [
            Vec2(-150, 150), Vec2(-70, 220), Vec2(10, 140), Vec2(-180, 20), Vec2(-60, 50),
            Vec2(70, 180), Vec2(-160, -80), Vec2(80, -30), Vec2(170, 90), Vec2(130, -110),
            Vec2(-30, -140), Vec2(200, 10),
        ]
        for s in spots { addShadeTree(at: center + s) }
        for s in [Vec2(-70, 100), Vec2(60, 20), Vec2(150, -50)] { addFlowers(at: center + s) }
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

        // arched stained-glass windows along the nave front, warmly lit
        let glassColors = [SKColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 1),
                           SKColor(red: 0.60, green: 0.78, blue: 0.95, alpha: 1),
                           SKColor(red: 0.70, green: 0.85, blue: 0.55, alpha: 1)]
        for (i, gx) in [-0.28, 0.06, 0.30].enumerated() {
            let win = SKNode(); win.position = CGPoint(x: w * CGFloat(gx), y: -d * 0.08)
            let body = SKShapeNode(rectOf: CGSize(width: 18, height: 30), cornerRadius: 2)
            body.fillColor = glassColors[i % glassColors.count]
            body.strokeColor = SKColor(white: 1, alpha: 0.7); body.lineWidth = 1.5; win.addChild(body)
            let arch = SKShapeNode(circleOfRadius: 9)
            arch.fillColor = body.fillColor; arch.strokeColor = body.strokeColor; arch.lineWidth = 1.5
            arch.position = CGPoint(x: 0, y: 15); win.addChild(arch)
            node.addChild(win)
        }
        // arched wooden door
        let door = SKShapeNode(rectOf: CGSize(width: 26, height: 34), cornerRadius: 13)
        door.fillColor = SKColor(red: 0.50, green: 0.33, blue: 0.20, alpha: 1)
        door.strokeColor = SKColor(white: 0, alpha: 0.25); door.lineWidth = 1.5
        door.position = CGPoint(x: w * 0.30, y: -d * 0.30); node.addChild(door)
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

    // MARK: - Wildlife (birds, squirrels, rabbits, bees) + their sounds

    /// Scatter a little wildlife through the park and grass: songbirds pecking,
    /// squirrels by the trees, rabbits on the lawn, and bees circling the flower
    /// beds. They idle via SKActions; `updateCritters` makes one chirp/scurry/hop
    /// every few seconds, and the flock startles up when the bus honks.
    private func buildWildlife() {
        for v in [Vec2(-120, 250), Vec2(150, 330), Vec2(-430, 110), Vec2(70, -360), Vec2(-250, -250), Vec2(360, 140)] {
            let b = makeBird(at: v); birds.append(b); worldNode.addChild(b)
        }
        for v in [Vec2(-600, 200), Vec2(120, 150), Vec2(-150, 250)] {
            let s = makeSquirrel(at: v); squirrels.append(s); worldNode.addChild(s)
        }
        for v in [Vec2(-360, 360), Vec2(430, -120), Vec2(-470, -200)] {
            let r = makeRabbit(at: v); rabbits.append(r); worldNode.addChild(r)
        }
        for v in [Vec2(-560, -430), Vec2(-150, 470), Vec2(330, 470), Vec2(-300, 130), Vec2(120, -250)] {
            addBees(at: v); beeClusters.append(v)
        }
    }

    private func makeBird(at v: Vec2) -> SKNode {
        let node = SKNode(); node.position = pt(v); node.zPosition = 7
        let palette = [SKColor(red: 0.86, green: 0.32, blue: 0.26, alpha: 1),   // robin red
                       SKColor(red: 0.32, green: 0.55, blue: 0.85, alpha: 1),   // bluebird
                       SKColor(red: 0.95, green: 0.78, blue: 0.30, alpha: 1)]   // finch yellow
        let c = palette.randomElement()!
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 16, height: 7))
        shadow.fillColor = SKColor(white: 0, alpha: 0.13); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 1, y: -7); node.addChild(shadow)
        let body = SKShapeNode(ellipseOf: CGSize(width: 15, height: 10))
        body.fillColor = c; body.strokeColor = .clear; node.addChild(body)
        let wing = SKShapeNode(ellipseOf: CGSize(width: 9, height: 6))
        wing.fillColor = c.withAlphaComponent(0.7); wing.strokeColor = .clear
        wing.position = CGPoint(x: -2, y: 1); node.addChild(wing)
        let head = SKShapeNode(circleOfRadius: 5)
        head.fillColor = c; head.strokeColor = .clear; head.position = CGPoint(x: 7, y: 4); node.addChild(head)
        let beak = SKShapeNode(path: { let p = CGMutablePath()
            p.move(to: CGPoint(x: 11, y: 5)); p.addLine(to: CGPoint(x: 16, y: 4))
            p.addLine(to: CGPoint(x: 11, y: 3)); p.closeSubpath(); return p }())
        beak.fillColor = SKColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1); beak.strokeColor = .clear
        node.addChild(beak)
        let eye = SKShapeNode(circleOfRadius: 1.3)
        eye.fillColor = .black; eye.strokeColor = .clear; eye.position = CGPoint(x: 8, y: 5); node.addChild(eye)
        node.run(.repeatForever(.sequence([                       // gentle pecking bob
            .moveBy(x: 0, y: -3, duration: 0.18), .moveBy(x: 0, y: 3, duration: 0.18),
            .wait(forDuration: Double.random(in: 0.5...1.6)),
        ])), withKey: "idle")
        return node
    }

    private func makeSquirrel(at v: Vec2) -> SKNode {
        let node = SKNode(); node.position = pt(v); node.zPosition = 7
        let fur = SKColor(red: 0.55, green: 0.38, blue: 0.26, alpha: 1)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 22, height: 9))
        shadow.fillColor = SKColor(white: 0, alpha: 0.13); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -7); node.addChild(shadow)
        let tail = SKShapeNode(ellipseOf: CGSize(width: 10, height: 20))
        tail.fillColor = fur.withAlphaComponent(0.85); tail.strokeColor = .clear
        tail.position = CGPoint(x: -11, y: 4)
        tail.run(.repeatForever(.sequence([.rotate(toAngle: 0.3, duration: 0.5), .rotate(toAngle: -0.1, duration: 0.5)])))
        node.addChild(tail)
        let body = SKShapeNode(ellipseOf: CGSize(width: 18, height: 11))
        body.fillColor = fur; body.strokeColor = .clear; node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = fur; head.strokeColor = .clear; head.position = CGPoint(x: 9, y: 4); node.addChild(head)
        for dx in [7.0, 11.0] {
            let ear = SKShapeNode(circleOfRadius: 2.2)
            ear.fillColor = fur; ear.strokeColor = .clear; ear.position = CGPoint(x: dx, y: 9); node.addChild(ear)
        }
        return node
    }

    private func makeRabbit(at v: Vec2) -> SKNode {
        let node = SKNode(); node.position = pt(v); node.zPosition = 7
        let fur = SKColor(white: 0.85, alpha: 1)
        let outline = SKColor(white: 0.6, alpha: 0.4)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 20, height: 8))
        shadow.fillColor = SKColor(white: 0, alpha: 0.13); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 1, y: -7); node.addChild(shadow)
        let body = SKShapeNode(ellipseOf: CGSize(width: 18, height: 12))
        body.fillColor = fur; body.strokeColor = outline; body.lineWidth = 1; node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = fur; head.strokeColor = .clear; head.position = CGPoint(x: 8, y: 4); node.addChild(head)
        let ears = SKNode(); ears.position = CGPoint(x: 9, y: 9)
        for dx in [-2.5, 2.5] {
            let ear = SKShapeNode(ellipseOf: CGSize(width: 3.5, height: 12))
            ear.fillColor = fur; ear.strokeColor = outline; ear.lineWidth = 1
            ear.position = CGPoint(x: dx, y: 4); ears.addChild(ear)
        }
        ears.run(.repeatForever(.sequence([.rotate(toAngle: 0.12, duration: 0.6), .rotate(toAngle: -0.12, duration: 0.6),
                                           .wait(forDuration: Double.random(in: 0.4...1.2))])))
        node.addChild(ears)
        let tail = SKShapeNode(circleOfRadius: 3.5)
        tail.fillColor = .white; tail.strokeColor = .clear; tail.position = CGPoint(x: -10, y: 2); node.addChild(tail)
        return node
    }

    /// A few bees lazily circling the flowers at `v` (the continuous buzz comes from
    /// the audio layer, swelling as the bus nears any flower bed).
    private func addBees(at v: Vec2) {
        let c = pt(v)
        for k in 0..<3 {
            let bee = SKNode(); bee.zPosition = 8
            let body = SKShapeNode(ellipseOf: CGSize(width: 6, height: 4))
            body.fillColor = SKColor(red: 0.96, green: 0.80, blue: 0.20, alpha: 1)
            body.strokeColor = SKColor(white: 0.1, alpha: 0.8); body.lineWidth = 0.8; bee.addChild(body)
            let wing = SKShapeNode(ellipseOf: CGSize(width: 4, height: 3))
            wing.fillColor = SKColor(white: 1, alpha: 0.6); wing.strokeColor = .clear
            wing.position = CGPoint(x: 0, y: 2); bee.addChild(wing)
            let r = CGFloat(16 + k * 7)
            bee.position = CGPoint(x: c.x + r, y: c.y)
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            bee.run(.repeatForever(.follow(path, asOffset: false, orientToPath: false,
                                           duration: 2.2 + Double(k) * 0.5)))
            worldNode.addChild(bee)
        }
    }

    /// The flock startles up and resettles when the bus honks.
    private func flutterBirds() {
        for b in birds {
            let dx = CGFloat.random(in: -22...22)
            b.run(.sequence([
                .group([.moveBy(x: dx, y: 46, duration: 0.45), .scaleX(to: 1.1, y: 0.85, duration: 0.2)]),
                .group([.moveBy(x: -dx, y: -46, duration: 0.55), .scale(to: 1.0, duration: 0.3)]),
            ]), withKey: "fly")
        }
        audio.play(.birdChirp)
    }

    private func bobBird(_ b: SKNode) {
        b.run(.sequence([.moveBy(x: 0, y: 10, duration: 0.12), .moveBy(x: 0, y: -10, duration: 0.12),
                         .moveBy(x: 0, y: 6, duration: 0.1), .moveBy(x: 0, y: -6, duration: 0.1)]), withKey: "fly")
    }

    private func scurry(_ s: SKNode) {
        let dx = CGFloat.random(in: 30...60) * CGFloat(Bool.random() ? 1 : -1)
        s.run(.sequence([.moveBy(x: dx, y: 0, duration: 0.3), .wait(forDuration: 0.4),
                         .moveBy(x: -dx, y: 0, duration: 0.4)]), withKey: "move")
    }

    private func hopRabbit(_ r: SKNode) {
        let dx = CGFloat.random(in: 18...36) * CGFloat(Bool.random() ? 1 : -1)
        r.run(.sequence([
            .group([.moveBy(x: dx / 2, y: 22, duration: 0.18), .scaleY(to: 1.1, duration: 0.18)]),
            .group([.moveBy(x: dx / 2, y: -22, duration: 0.2), .scaleY(to: 1.0, duration: 0.2)]),
        ]), withKey: "move")
    }

    // MARK: - Pedestrians & honk reactions

    private func buildPeds() {
        // Onlookers ringing the loop + clustered at the park and bus stop, so the
        // bus is always near a few and honk reactions land on camera.
        let homes: [Vec2] = [
            Vec2(-400, -600), Vec2(300, -600),       // along Montrose (inside)
            Vec2(-400, 600), Vec2(300, 600),         // along Sunnyside (inside)
            Vec2(-690, -300), Vec2(-690, 300),       // along Western (inside)
            Vec2(520, -560), Vec2(560, 300),         // toward Lincoln (inside)
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

    private func makePersonNode(height: CGFloat) -> SKNode {
        let node = SKNode()
        let shadow = SKShapeNode(circleOfRadius: height * 0.36)
        shadow.fillColor = SKColor(white: 0, alpha: 0.15); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 3, y: -height * 0.18); node.addChild(shadow)
        node.addChild(kenneySprite(kenneyCharacters.randomElement()!, height: height))
        return node
    }

    /// Animated park life that isn't part of the honk-reactor crowd: joggers looping
    /// the central walk, dogs trotting little circuits, and parents strolling with a
    /// child. All move via SKActions (no per-frame code) and keep off the roads.
    private func buildParkLife() {
        // joggers running a clear lane west of the fieldhouse
        for (i, x) in [-330.0, -300.0].enumerated() {
            let r = makePersonNode(height: 32); r.position = pt(Vec2(x, -360)); r.zPosition = 8
            worldNode.addChild(r)
            let dur = 8.0 + Double(i) * 2
            r.run(.repeatForever(.sequence([.move(to: pt(Vec2(x, 320)), duration: dur),
                                            .move(to: pt(Vec2(x, -360)), duration: dur)])))
            r.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.18),
                                            .moveBy(x: 0, y: -5, duration: 0.16)])))
        }
        // (swimmers are built into the pool; the ball fields field their own teams.)
        // a tennis match on the east hard-court — racket sport stays ON the courts
        addTennisPlayers(at: Vec2(220, 10))
        // people lounging on the grass (towels)
        for c in [Vec2(-360, -380), Vec2(-180, 360), Vec2(450, -40)] { addLounger(at: c) }
        // people resting on the benches by the walk
        addSitter(at: Vec2(-220, -120)); addSitter(at: Vec2(-80, 240))
        // dogs trotting + families strolling, in open grass
        for c in [Vec2(-400, 180), Vec2(150, 170), Vec2(-150, -430)] { addDog(at: c) }
        for c in [Vec2(-300, -180), Vec2(-430, 40), Vec2(60, -440)] { addFamily(at: c) }
    }

    /// A swimmer doing laps ALONG a pool lane: head + cap with a little bow-wave,
    /// added as a child of the (un-rotated) pool node at a lane's local point, so it
    /// rides the painted lane and swims left–right (the way the lanes run).
    private func addSwimmer(to parent: SKNode, at p: CGPoint, span: CGFloat, phase: Double) {
        let node = SKNode(); node.position = CGPoint(x: p.x - span / 2, y: p.y); node.zPosition = 6
        let splash = SKShapeNode(ellipseOf: CGSize(width: 16, height: 9))
        splash.fillColor = SKColor(white: 1, alpha: 0.6); splash.strokeColor = .clear
        splash.position = CGPoint(x: -7, y: 0); node.addChild(splash)
        let head = SKShapeNode(circleOfRadius: 5)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        node.addChild(head)
        let cap = SKShapeNode(circleOfRadius: 5)
        cap.fillColor = SKColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 0.5); cap.strokeColor = .clear
        cap.position = CGPoint(x: 0, y: 1); node.addChild(cap)
        node.run(.sequence([.wait(forDuration: phase), .repeatForever(.sequence([
            .moveBy(x: span, y: 0, duration: 2.4), .moveBy(x: -span, y: 0, duration: 2.4)]))]))
        splash.run(.repeatForever(.sequence([.scale(to: 1.3, duration: 0.3), .scale(to: 0.9, duration: 0.3)])))
        parent.addChild(node)
    }

    /// A tennis rally on a court: two kids either side of the net with a ball that
    /// lobs back and forth — so the racket sport reads as happening ON the courts.
    private func addTennisPlayers(at v: Vec2) {
        for dx in [-58.0, 58.0] { addKid(at: v + Vec2(dx, 0)) }
        let ball = SKShapeNode(circleOfRadius: 5)
        ball.fillColor = SKColor(red: 0.85, green: 0.95, blue: 0.35, alpha: 1)
        ball.strokeColor = SKColor(white: 0, alpha: 0.3); ball.lineWidth = 1
        ball.position = pt(v + Vec2(-58, 0)); ball.zPosition = 9; worldNode.addChild(ball)
        ball.run(.repeatForever(.sequence([
            .move(to: pt(v + Vec2(58, 24)), duration: 0.6), .move(to: pt(v + Vec2(58, 0)), duration: 0.1),
            .move(to: pt(v + Vec2(-58, 24)), duration: 0.6), .move(to: pt(v + Vec2(-58, 0)), duration: 0.1),
        ])))
    }

    /// A person lounging on a towel on the grass.
    private func addLounger(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 7
        let towel = SKShapeNode(rectOf: CGSize(width: 46, height: 26), cornerRadius: 4)
        towel.fillColor = [SKColor(red: 0.95, green: 0.5, blue: 0.5, alpha: 1),
                           SKColor(red: 0.45, green: 0.7, blue: 0.95, alpha: 1),
                           SKColor(red: 0.98, green: 0.85, blue: 0.4, alpha: 1)].randomElement()!
        towel.strokeColor = .clear; node.addChild(towel)
        let body = SKShapeNode(rectOf: CGSize(width: 34, height: 12), cornerRadius: 6)
        body.fillColor = SKColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1); body.strokeColor = .clear
        body.position = CGPoint(x: -2, y: 0); node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = SKColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1); head.strokeColor = .clear
        head.position = CGPoint(x: 16, y: 0); node.addChild(head)
        worldNode.addChild(node)
    }

    /// A person sitting still on a bench (a gentle idle).
    private func addSitter(at v: Vec2) {
        let p = makePersonNode(height: 28); p.position = pt(v + Vec2(0, 6)); p.zPosition = 7
        p.run(.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 1.0), .moveBy(x: 0, y: -2, duration: 1.0)])))
        worldNode.addChild(p)
    }

    /// A small dog that trots a little loop, tail wagging.
    private func addDog(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 8
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 26, height: 12))
        shadow.fillColor = SKColor(white: 0, alpha: 0.14); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -8); node.addChild(shadow)
        let coat = SKColor(red: 0.55, green: 0.40, blue: 0.26, alpha: 1)
        let body = SKShapeNode(ellipseOf: CGSize(width: 26, height: 14))
        body.fillColor = coat; body.strokeColor = .clear; node.addChild(body)
        let head = SKShapeNode(circleOfRadius: 7)
        head.fillColor = coat; head.strokeColor = .clear; head.position = CGPoint(x: 13, y: 4); node.addChild(head)
        let ear = SKShapeNode(ellipseOf: CGSize(width: 5, height: 9))
        ear.fillColor = SKColor(red: 0.42, green: 0.30, blue: 0.20, alpha: 1); ear.strokeColor = .clear
        ear.position = CGPoint(x: 13, y: 9); node.addChild(ear)
        let tail = SKShapeNode(rectOf: CGSize(width: 10, height: 3), cornerRadius: 1.5)
        tail.fillColor = coat; tail.strokeColor = .clear; tail.position = CGPoint(x: -14, y: 4)
        tail.run(.repeatForever(.sequence([.rotate(toAngle: 0.5, duration: 0.18),
                                           .rotate(toAngle: -0.2, duration: 0.18)])))
        node.addChild(tail)
        worldNode.addChild(node)
        node.run(.repeatForever(.sequence([
            .move(to: pt(v + Vec2(90, 0)), duration: 3), .move(to: pt(v + Vec2(90, 90)), duration: 3),
            .move(to: pt(v + Vec2(0, 90)), duration: 3), .move(to: pt(v), duration: 3),
        ])))
    }

    /// A parent and child walking together, ambling slowly back and forth.
    private func addFamily(at v: Vec2) {
        let group = SKNode(); group.position = pt(v); group.zPosition = 8
        let adult = makePersonNode(height: 36); adult.position = CGPoint(x: -10, y: 0); group.addChild(adult)
        let child = makePersonNode(height: 24); child.position = CGPoint(x: 16, y: -4); group.addChild(child)
        worldNode.addChild(group)
        group.run(.repeatForever(.sequence([
            .move(to: pt(v + Vec2(120, 20)), duration: 8), .move(to: pt(v), duration: 8),
        ])))
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
        audio.play(.horn)
        flutterBirds()           // the flock startles up and resettles
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
        updateAudio(dt: dt)
        syncNodes()
        updateCamera()
        updatePerspectiveBuilding()
        updateBeacon()
    }

    // MARK: - Audio drive (per-frame, continuous signals + ambient life)

    private func updateAudio(dt: Double) {
        // Engine hum tracks speed; bee buzz swells near the flower beds.
        audio.setEngineIntensity(min(1, bus.speed / max(1, bus.maxSpeed)))
        let beeDist = beeClusters.map { bus.position.distance(to: $0) }.min() ?? .infinity
        audio.setBeeIntensity(max(0, 1 - beeDist / 240))

        // A soft whoosh when the oncoming car rolls past (edge-triggered).
        let carNear = bus.position.distance(to: car.position) < 150
        if carNear, !carWasNear { audio.play(.carPass) }
        carWasNear = carNear

        updateLightAudio()
        updateCritters(dt: dt)
    }

    /// The pedestrian-crossing + traffic-light countdown audio. When the bus is near
    /// a corner: the light going red signals "wait, let them cross"; while red it
    /// ticks down 3… 2… 1…; turning green is a happy "go!".
    private func updateLightAudio() {
        let nearCorner = RoadNetwork.wellesCorners.map { bus.position.distance(to: $0) }.min() ?? .infinity
        let near = nearCorner < 340

        if light.state != prevLightState {
            if light.state == .red, near {
                audio.play(.crossingWait)
                showCrossingPrompt("crossing.wait")
            } else if light.state == .green, near {
                audio.play(.lightGo)
                audio.play(.crossingWalk)
                showCrossingPrompt("crossing.go")
            }
            prevLightState = light.state
            lastCountdownSecond = -1
        }

        if near, light.state == .red {
            let sec = Int(ceil(light.secondsUntilChange))
            if sec >= 1, sec <= 3, sec != lastCountdownSecond {
                lastCountdownSecond = sec
                audio.play(.lightCountdown)
            }
        }
    }

    /// Show a brief crossing prompt — but only if nothing else is being said, so it
    /// never steps on an episode line.
    private func showCrossingPrompt(_ lineId: String) {
        guard (hud?.subtitle ?? "").isEmpty else { return }
        hud?.subtitle = localizer.string(lineId, language)
        hud?.speakerName = localizer.string("mom.name", language)
        hud?.speakerColorHex = "#2ea59e"
        subtitleClearAt = elapsed + 2.0
    }

    /// Every few seconds a critter makes itself heard and does a little move — so
    /// the town always sounds (and looks) alive. Kept gentle so the birds don't
    /// chatter over the music.
    private func updateCritters(dt: Double) {
        critterTimer += dt
        guard critterTimer >= nextCritterDelay else { return }
        critterTimer = 0
        nextCritterDelay = Double.random(in: 3.8...7.5)
        switch Int.random(in: 0..<10) {
        case 0..<3:
            audio.play(Bool.random() ? .birdChirp : .birdSong)
            if let b = birds.randomElement() { bobBird(b) }
        case 3..<6:
            audio.play(.squirrelChitter)
            if let s = squirrels.randomElement() { scurry(s) }
        default:
            audio.play(.rabbitThump)
            if let r = rabbits.randomElement() { hopRabbit(r) }
        }
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
        publishMinimap()
    }

    /// Feed the SwiftUI minimap the bus's world position/heading and the current
    /// goal. Throttled so it only republishes when something visibly moves, to keep
    /// SwiftUI from re-laying-out the HUD on every single frame.
    private var lastMiniPublish = MinimapState()
    private func publishMinimap() {
        guard let hud else { return }
        var st = MinimapState(busX: bus.position.x, busZ: bus.position.z, heading: bus.heading)
        if let g = episodeTarget { st.goalX = g.position.x; st.goalZ = g.position.z }
        if abs(st.busX - lastMiniPublish.busX) > 1.5
            || abs(st.busZ - lastMiniPublish.busZ) > 1.5
            || abs(st.heading - lastMiniPublish.heading) > 0.03
            || st.goalX != lastMiniPublish.goalX || st.goalZ != lastMiniPublish.goalZ {
            lastMiniPublish = st
            hud.minimap = st
        }
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
        // An overhead mast-arm signal at each park corner. The arm reaches OUT over
        // the road the bus approaches on; the head HANGS over that lane facing the
        // oncoming bus (its visors/hoods point right at the driver); and a bold
        // arrow on the deck points the way that flow travels. Together those make it
        // obvious which light governs which direction. A soft drop-shadow lifts the
        // overhead gear off the road for a little faked perspective. All four heads
        // share one phase (cornerLamps drives the render).
        //
        // Per corner (NW, NE, SE, SW) in screen space (y is up; north is +y):
        //   reach  — pole → out over the road the bus is on
        //   face   — the lit side, pointing back at the oncoming bus
        //   travel — the way that flow drives (the arrow)
        let reach:  [CGVector] = [CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1),
                                  CGVector(dx: 0.98, dy: 0.20), CGVector(dx: 0, dy: -1)]
        let face:   [CGVector] = [CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0),
                                  CGVector(dx: -0.20, dy: 0.98), CGVector(dx: 1, dy: 0)]
        let travel: [CGVector] = [CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0),
                                  CGVector(dx: 0.20, dy: -0.98), CGVector(dx: -1, dy: 0)]
        for (i, c) in RoadNetwork.wellesCorners.enumerated() {
            let inset = Vec2(c.x > 0 ? -56 : 56, c.z > 0 ? -56 : 56)
            let node = SKNode(); node.position = pt(c + inset); node.zPosition = 7
            let rch = reach[i], fac = face[i], trv = travel[i]
            let armLen: CGFloat = 72
            let armEnd = CGPoint(x: rch.dx * armLen, y: rch.dy * armLen)

            // the curb post (a small footprint, seen from above)
            let post = SKShapeNode(circleOfRadius: 8)
            post.fillColor = SKColor(white: 0.34, alpha: 1); post.strokeColor = SKColor(white: 0, alpha: 0.3)
            post.lineWidth = 1.5; node.addChild(post)

            // a soft shadow of the arm + head, offset down-right so the gear reads as
            // hanging over the road
            let shadowOff = CGPoint(x: 5, y: -5)
            let armShadow = SKShapeNode(); let sp = CGMutablePath()
            sp.move(to: shadowOff); sp.addLine(to: CGPoint(x: armEnd.x + shadowOff.x, y: armEnd.y + shadowOff.y))
            armShadow.path = sp; armShadow.strokeColor = SKColor(white: 0, alpha: 0.16); armShadow.lineWidth = 7
            armShadow.lineCap = .round; node.addChild(armShadow)
            let headShadow = SKShapeNode(rectOf: CGSize(width: 70, height: 30), cornerRadius: 8)
            headShadow.fillColor = SKColor(white: 0, alpha: 0.16); headShadow.strokeColor = .clear
            headShadow.position = CGPoint(x: armEnd.x + shadowOff.x, y: armEnd.y + shadowOff.y); node.addChild(headShadow)

            // the mast arm reaching over the road
            let arm = SKShapeNode(); let ap = CGMutablePath()
            ap.move(to: .zero); ap.addLine(to: armEnd)
            arm.path = ap; arm.strokeColor = SKColor(white: 0.42, alpha: 1); arm.lineWidth = 5
            arm.lineCap = .round; node.addChild(arm)

            // the signal head, hung from the arm end, turned to face the oncoming bus
            let head = SKNode(); head.position = armEnd
            head.zRotation = atan2(-fac.dx, fac.dy)          // local +y → fac
            let housing = SKShapeNode(rectOf: CGSize(width: 66, height: 26), cornerRadius: 7)
            housing.fillColor = SKColor(white: 0.14, alpha: 1)
            housing.strokeColor = SKColor(white: 0, alpha: 0.35); housing.lineWidth = 2
            head.addChild(housing)
            func lamp(_ x: CGFloat, _ color: SKColor) -> SKShapeNode {
                let visor = SKShapeNode(rectOf: CGSize(width: 19, height: 7), cornerRadius: 3)
                visor.fillColor = SKColor(white: 0.05, alpha: 1); visor.strokeColor = .clear
                visor.position = CGPoint(x: x, y: 9); head.addChild(visor)   // hood on the facing side
                let l = SKShapeNode(circleOfRadius: 8.5)
                l.fillColor = color; l.strokeColor = .clear; l.position = CGPoint(x: x, y: 0)
                head.addChild(l); return l
            }
            let r  = lamp(-20, SKColor(red: 0.92, green: 0.24, blue: 0.22, alpha: 1))
            let y  = lamp(0,   SKColor(red: 0.96, green: 0.80, blue: 0.24, alpha: 1))
            let gr = lamp(20,  SKColor(red: 0.30, green: 0.80, blue: 0.36, alpha: 1))
            node.addChild(head)
            cornerLamps.append((r, y, gr))

            // A second, near-side signal on a short curb pole, so each intersection
            // has TWO stoplights (overhead + curb) like the real corner. Same phase.
            cornerLamps.append(addNearSignal(to: node, face: fac, reach: rch))

            // a bold arrow painted on the deck under the head, pointing the way this
            // flow travels — the at-a-glance "this signal is for traffic going THAT
            // way" cue.
            let arrow = directionArrow(dir: trv)
            arrow.position = CGPoint(x: armEnd.x - trv.dx * 30, y: armEnd.y - trv.dy * 30)
            arrow.zPosition = -0.5; node.addChild(arrow)

            worldNode.addChild(node)
        }
        updateLightRender()
    }

    /// A compact second signal head on a short curb pole, set back from the road on
    /// the corner and facing the oncoming bus — the near-side mate to the overhead
    /// mast-arm head. Returns its lamps so `cornerLamps` keeps it in phase.
    private func addNearSignal(to node: SKNode, face fac: CGVector,
                               reach rch: CGVector) -> (red: SKShapeNode, yellow: SKShapeNode, green: SKShapeNode) {
        // a stubby post on the curb, back from the road (opposite the arm's reach)
        let basePos = CGPoint(x: -rch.dx * 12, y: -rch.dy * 12)
        let post = SKShapeNode(circleOfRadius: 6)
        post.fillColor = SKColor(white: 0.34, alpha: 1); post.strokeColor = SKColor(white: 0, alpha: 0.3)
        post.lineWidth = 1.5; post.position = basePos; node.addChild(post)

        let headShadow = SKShapeNode(rectOf: CGSize(width: 50, height: 20), cornerRadius: 6)
        headShadow.fillColor = SKColor(white: 0, alpha: 0.16); headShadow.strokeColor = .clear
        headShadow.position = CGPoint(x: basePos.x + 4, y: basePos.y - 4); node.addChild(headShadow)

        let head = SKNode(); head.position = basePos
        head.zRotation = atan2(-fac.dx, fac.dy)          // local +y → fac (faces the bus)
        let housing = SKShapeNode(rectOf: CGSize(width: 50, height: 20), cornerRadius: 6)
        housing.fillColor = SKColor(white: 0.14, alpha: 1)
        housing.strokeColor = SKColor(white: 0, alpha: 0.35); housing.lineWidth = 1.5
        head.addChild(housing)
        func lamp(_ x: CGFloat, _ color: SKColor) -> SKShapeNode {
            let visor = SKShapeNode(rectOf: CGSize(width: 14, height: 5), cornerRadius: 2)
            visor.fillColor = SKColor(white: 0.05, alpha: 1); visor.strokeColor = .clear
            visor.position = CGPoint(x: x, y: 7); head.addChild(visor)
            let l = SKShapeNode(circleOfRadius: 6.5)
            l.fillColor = color; l.strokeColor = .clear; l.position = CGPoint(x: x, y: 0)
            head.addChild(l); return l
        }
        let r  = lamp(-15, SKColor(red: 0.92, green: 0.24, blue: 0.22, alpha: 1))
        let y  = lamp(0,   SKColor(red: 0.96, green: 0.80, blue: 0.24, alpha: 1))
        let gr = lamp(15,  SKColor(red: 0.30, green: 0.80, blue: 0.36, alpha: 1))
        node.addChild(head)
        return (r, y, gr)
    }

    /// A bold lane chevron pointing in screen-direction `dir` (the art points +y).
    private func directionArrow(dir: CGVector) -> SKNode {
        let n = SKNode()
        n.zRotation = atan2(dir.dy, dir.dx) - .pi / 2
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 13)); p.addLine(to: CGPoint(x: -10, y: -1))
        p.addLine(to: CGPoint(x: -4, y: -1)); p.addLine(to: CGPoint(x: -4, y: -13))
        p.addLine(to: CGPoint(x: 4, y: -13)); p.addLine(to: CGPoint(x: 4, y: -1))
        p.addLine(to: CGPoint(x: 10, y: -1)); p.closeSubpath()
        let a = SKShapeNode(path: p)
        a.fillColor = SKColor(red: 0.98, green: 0.92, blue: 0.42, alpha: 0.95)
        a.strokeColor = SKColor(white: 0.1, alpha: 0.55); a.lineWidth = 1
        n.addChild(a)
        return n
    }

    private func updateLightRender() {
        for set in cornerLamps {
            set.red.alpha = light.state == .red ? 1.0 : 0.16
            set.yellow.alpha = light.state == .yellow ? 1.0 : 0.16
            set.green.alpha = light.state == .green ? 1.0 : 0.16
        }
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
        addLibrarySign(at: perspCenter - Vec2(170, 0))   // monument sign toward Lincoln Ave
    }

    /// A little monument sign in front of the library: a board on two posts with a
    /// wordless open-book icon, so the landmark reads as the library from the road.
    private func addLibrarySign(at v: Vec2) {
        let node = SKNode(); node.position = pt(v); node.zPosition = 6
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 64, height: 20))
        shadow.fillColor = SKColor(white: 0, alpha: 0.14); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 4, y: -22); node.addChild(shadow)
        for dx in [-22.0, 22.0] {
            let post = SKShapeNode(rectOf: CGSize(width: 6, height: 30), cornerRadius: 2)
            post.fillColor = SKColor(red: 0.45, green: 0.32, blue: 0.20, alpha: 1); post.strokeColor = .clear
            post.position = CGPoint(x: CGFloat(dx), y: -16); node.addChild(post)
        }
        let board = SKShapeNode(rectOf: CGSize(width: 70, height: 40), cornerRadius: 6)
        board.fillColor = SKColor(red: 0.42, green: 0.55, blue: 0.42, alpha: 1)
        board.strokeColor = SKColor(white: 1, alpha: 0.8); board.lineWidth = 2.5; node.addChild(board)
        let icon = bookIcon(); icon.setScale(1.15); node.addChild(icon)
        worldNode.addChild(node)
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
