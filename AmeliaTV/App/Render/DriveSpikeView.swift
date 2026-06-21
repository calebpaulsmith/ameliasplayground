import SwiftUI
import AmeliaCore

#if canImport(RealityKit)
import RealityKit
#if canImport(UIKit)
import UIKit
#endif

/// Phase 2 playable view: runs the "First Day" episode through `GameSession` and
/// renders it with RealityKit — a placeholder bus auto-drives the route, speaks
/// (AVSpeech), and shows the `HUDView` (GO/STOP, turn arrow, stars, subtitle,
/// minimap) plus a floating destination beacon. Art is placeholder; the full
/// neighborhood scene, garage and reward screens are the next steps.
///
/// Requires the tvOS 26 SDK (RealityKit on tvOS); a SwiftUI fallback compiles on
/// older SDKs so the project always builds.
struct DriveSpikeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = SpikeEngine()

    var body: some View {
        ZStack {
            RealityView { content in
                content.add(engine.makeRoot())
            }
            .ignoresSafeArea()

            HUDView(model: engine.hud,
                    onTurnLeft: { engine.chooseTurn(.left) },
                    onTurnRight: { engine.chooseTurn(.right) },
                    onContinue: { dismiss() })
                .environmentObject(session)

            // The manual "back" affordance is hidden once the reward screen owns
            // the view (it has its own big "back to the garage" button).
            if !engine.hud.finished {
                Button(session.string("ui.back")) { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .onAppear { engine.start(session: session) }
        .onDisappear { engine.stop() }
    }
}

/// A neighborhood character (ambient friend or the episode rider) plus the small
/// eased/sprung state that gives it life — kept next to its entity so the engine
/// can animate it each frame. Pure data; the Core is untouched (GAME_DESIGN §4a).
private final class CharacterActor {
    let node: Entity
    let face: FaceRig
    let waveArm: Entity
    var home: SIMD3<Float>
    let baseYaw: Double
    let phase: Double            // idle-bob phase, staggered so they don't sync
    var nextBlink: Double
    var blinkUntil: Double = -1
    var look: Double = 0         // eased pupil glance
    var yaw: Double              // eased turn-to-watch
    var wave: Double = 0         // eased wave amount (0…1)
    var hop = SpringValue(stiffness: 200, damping: 14)

    init(rig: (root: Entity, face: FaceRig, waveArm: Entity), home: SIMD3<Float>, baseYaw: Double) {
        node = rig.root
        face = rig.face
        waveArm = rig.waveArm
        self.home = home
        self.baseYaw = baseYaw
        yaw = baseYaw
        phase = Double.random(in: 0 ... (2 * Double.pi))
        nextBlink = Double.random(in: 1.0...4.0)
    }
}

/// Owns the GameSession, the RealityKit entities, and the per-frame loop. Kept
/// out of SwiftUI so it can mutate entity transforms directly each tick.
@MainActor
final class SpikeEngine: ObservableObject {
    /// One published snapshot the HUD observes; rebuilt each frame, assigned only
    /// when it changes so SwiftUI isn't churned 60 times a second.
    @Published var hud = HUDModel()

    private let input = GameControllerInput()
    private let speaker = SpeechSpeaker()
    private let audio = ProceduralAudio()
    private var game: GameSession?
    private var places: [Place] = []

    private let root = Entity()
    private var bus = Entity()
    private var face: FaceRig?            // Amelia's eyes, for blink + look-at
    private var camera = Entity()
    private var beacon = Entity()
    private var neighborhood: NeighborhoodScene?
    private var timer: Timer?
    private var lastTick = Date()
    private var elapsed: Double = 0

    // The episode passenger ("rider") who waits at the stop, boards, then exits,
    // plus the ambient NPC friends who live around the neighborhood. All are given
    // life (idle-bob, blink, turn-to-watch, wave) by `animateCharacter`.
    private var friends: [CharacterActor] = []
    private var riderActor: CharacterActor?
    private var plan: GameSession.PassengerPlan?
    private var pickupPos: Vec2?
    private var dropoffPos: Vec2?
    private var riderBoardedOnce = false
    private var riderGreeted = false  // one-shot excited hop as the bus pulls up
    private var spokeReward = false   // speak Mom's praise once, when the episode ends

    // Collectibles (balloons / coins) scattered along the route; hidden once the
    // bus scoops them. Each entry keeps the collectible id so we can ask the game.
    private var collectibleNodes: [(id: String, node: Entity)] = []

    // A turn picked by an on-screen (touch) button, consumed on the next tick.
    // Lets the fork choice be made without a controller (e.g. on iPad).
    private var pendingTouchTurn: InputIntents.DiscreteTurn = .none

    // The in-world "spot it" beat: coloured balloons float ahead of the bus and the
    // child steers to aim at one and beeps the horn to pick it — selection is the
    // bus's own verbs (steer + honk), so it's part of driving and works on every
    // controller and the Siri Remote. No floating cards.
    private var findRig: Entity?                                  // follows the bus's facing
    private var findBalloons: [(id: String, node: Entity)] = []  // left→right, in option order
    private var findAimIndex = 0                                 // which balloon is highlighted
    private var findActive = false

    // --- Character Life: Amelia's expressive state (GAME_DESIGN.md §4a). ---
    // Springs/eased values driven each frame; springs give the playful "boing".
    private var lean = 0.0                          // roll into turns
    private var squash = SpringValue(stiffness: 220, damping: 16)   // squash on a stop
    private var hop = SpringValue(stiffness: 200, damping: 14)      // bounce on pickup/honk
    private var lookX = 0.0, lookY = 0.0            // eased pupil gaze
    private var wiggle = 0.0                        // honk happy-wiggle
    private var nextBlink = 1.5
    private var blinkUntil = -1.0
    private var prevSpeed = 0.0
    private var prevPassengerId: String?
    private var prevDrivePrompt: GameSession.DrivePrompt = .go
    private var prevSparkleCount = 0                 // star-award edge for sparkle bursts
    private var dustAccum = 0.0                      // throttles rolling-dust puffs
    private var cameraKick = SpringValue(stiffness: 90, damping: 11)  // bounce on big moments
    private let juice = JuiceEmitter()               // hand-animated sparkle/heart/dust bursts
    private let sun = DirectionalLight()             // dimmed at night by updateMood
    private let fill = DirectionalLight()            // constant soft fill (never go black)
    private var headlights: [ModelEntity] = []       // bus lamps, glow at night
    private var moodNight: Float = -1                // throttles night material updates
    private var reduceMotion = false                // tvOS "Reduce Motion" accessibility

    /// Called by the HUD's on-screen LEFT/RIGHT buttons.
    func chooseTurn(_ turn: InputIntents.DiscreteTurn) { pendingTouchTurn = turn }

    /// Maps Game Core ground units to RealityKit meters for a couch-scale view.
    private let scale: Float = 0.12

    func makeRoot() -> Entity {
        let rig = ModelLibrary.busRig(placeholderColor: .init(red: 0.23, green: 0.63, blue: 1.0, alpha: 1))
        bus = rig.root
        face = rig.face
        bus.position = [0, 0.55, 0]
        root.addChild(bus)

        // Headlights on the bus's forward (+x) face — dim by day, glowing at night
        // (driven by `updateMood`); unlit so they read as lit lamps.
        for z in [Float(-0.28), 0.28] {
            let hl = ModelLibrary.sphere(radius: 0.12, color: .white)
            hl.scale = [0.4, 0.9, 0.9]
            hl.position = [0.82, 0.30, z]
            bus.addChild(hl)
            headlights.append(hl)
        }

        // A bright floating pillar marking where to drive next. Hidden until the
        // episode sets a target; it bobs gently so a young child can spot it.
        beacon = ModelLibrary.placeholderBox(
            color: .init(red: 1.0, green: 0.82, blue: 0.25, alpha: 1),
            size: [0.25, 2.4, 0.25]
        )
        beacon.isEnabled = false
        root.addChild(beacon)

        // The sun (dimmed at night by `updateMood`) plus a constant soft fill so the
        // world never goes black — readability is a hard constraint for young kids.
        sun.light.intensity = 4200
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0.4, 0])
        root.addChild(sun)

        fill.light.intensity = 1500
        fill.orientation = simd_quatf(angle: -.pi / 4, axis: [-0.6, 0.5, -0.3])
        root.addChild(fill)

        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 55
        camera = cam
        root.addChild(camera)

        root.addChild(juice.root)

        positionCamera()
        return root
    }

    func start(session: AppSession) {
        let game = GameSession(
            content: session.content,
            save: session.save,
            speaker: speaker,
            sound: audio,
            persist: { [weak session] slot in
                Task { @MainActor in session?.persist(slot) }
            }
        )
        game.language = session.language
        game.start(episodeId: "first-day")
        self.game = game
        self.places = session.content.places
        self.spokeReward = false
        friends.removeAll()
        riderActor = nil
        riderBoardedOnce = false
        riderGreeted = false
        prevSparkleCount = 0
        moodNight = -1
        findActive = false
        clearFindBalloons()
        #if canImport(UIKit)
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        #endif

        // Build the data-driven neighborhood now that content is available, and
        // insert it beneath the already-rendered bus/beacon/camera.
        let scene = NeighborhoodScene(content: session.content, scale: scale)
        neighborhood = scene
        root.addChild(scene.root)

        buildPassengers(session: session, game: game)
        buildCollectibles(session: session)

        lastTick = Date()
        // The timer fires on the main run loop, so step runs synchronously on the
        // main actor — no per-frame `Task` hop (which adds latency/jank and can
        // pile up under load). assumeIsolated is valid because we're on main.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        speaker.stopSpeaking()
        audio.stopAll()
    }

    private func step() {
        guard let game else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 1.0 / 20.0)
        lastTick = now
        elapsed += dt

        var intents = input.currentIntents()
        if intents.discreteTurn == .none, pendingTouchTurn != .none {
            intents.discreteTurn = pendingTouchTurn
        }
        pendingTouchTurn = .none
        let honk = intents.honkPressed
        game.tick(dt: dt, input: intents)

        // When the episode finishes, Mom praises the player once (reward screen).
        if game.finished && !spokeReward {
            spokeReward = true
            game.dialogue.play("reward.complete", force: true)
        }

        // Give Amelia life: blink, look around, lean into turns, squash on stops,
        // breathe when idle, hop on pickup, wiggle on a honk (GAME_DESIGN.md §4a).
        updateBusLife(game: game, honk: honk, dt: dt)

        let p = game.bus.position
        bus.position = [Float(p.x) * scale, 0.55 + Float(hop.value), Float(p.z) * scale]
        let yaw = simd_quatf(angle: Float(-game.bus.heading), axis: [0, 1, 0])
        let leanRoll = simd_quatf(angle: Float(lean), axis: [1, 0, 0])   // tilt into the turn
        let honkWiggle = simd_quatf(angle: Float(wiggle), axis: [0, 1, 0])
        bus.orientation = yaw * leanRoll * honkWiggle
        let wide = Float(1 + squash.value * 0.5)
        let tall = Float(max(0.5, 1 - squash.value))
        bus.scale = [wide, tall, wide]

        // Engine hum rises and falls with how fast Amelia is rolling.
        audio.setEngineIntensity(abs(game.bus.speed) / game.core.assistLevel.maxSpeed)

        // Juice: a sparkle shower whenever a star is earned (edge-detected).
        if game.sparkleCount > prevSparkleCount {
            if !reduceMotion { juice.burst(at: bus.position + [0, 1.2, 0], kind: .sparkle, count: 12) }
            prevSparkleCount = game.sparkleCount
        }
        // Honk sends up a little puff of hearts and bounces the camera.
        if honk && !reduceMotion {
            juice.burst(at: bus.position + [0, 1.5, 0], kind: .heart, count: 6)
            cameraKick.nudge(2.2)
        }

        updateBeacon(target: game.currentTarget)
        if honk { neighborhood?.honk(busPos: bus.position) }
        for friend in friends { animateCharacter(friend, busPos: bus.position, dt: dt, honk: honk) }
        updateRider(game: game, busPos: bus.position, dt: dt, honk: honk)
        updateCollectibles(game: game)
        updateFindBeat(game: game, steer: intents.steer, pick: honk || intents.confirmPressed)
        juice.update(dt: Float(dt))
        neighborhood?.updateLights(game.lightSnapshot())
        neighborhood?.updateAmbient(elapsed: elapsed, dt: dt)
        updateMood()
        positionCamera()
        publishHUD(game)
    }

    /// Slowly washes the world from day to a gentle, readable night and back: the sun
    /// dims while windows, lamps, stars and the bus headlights glow. Held at bright
    /// day under Reduce Motion so the scene stays calm and predictable.
    private func updateMood() {
        let night: Float
        if reduceMotion {
            night = 0
        } else {
            let daylight = 0.5 + 0.5 * cos(elapsed * 2 * .pi / 220)   // 1 day → 0 night
            night = Float(1 - daylight) * 0.8                          // capped: never fully dark
        }
        sun.light.intensity = 4200 - 2200 * night

        guard abs(night - moodNight) >= 0.015 else { return }
        moodNight = night
        let b = 0.22 + 0.78 * night                                    // headlight brightness
        let lamp = UnlitMaterial(color: PlatformColor(red: CGFloat(b), green: CGFloat(b * 0.95),
                                                      blue: CGFloat(b * 0.8), alpha: 1))
        for hl in headlights { hl.model?.materials = [lamp] }
        neighborhood?.setNight(night)
    }

    /// Drives Amelia's personality each frame from Core state — eased values and
    /// springs so motion overshoots and settles instead of snapping. All gated by
    /// Reduce Motion; the Core is untouched (this only reads its state).
    private func updateBusLife(game: GameSession, honk: Bool, dt: Double) {
        let maxSpeed = max(0.001, game.core.assistLevel.maxSpeed)
        let speed = abs(game.bus.speed)
        let moving = min(1.0, speed / maxSpeed)
        let busGround = SIMD3<Float>(Float(game.bus.position.x) * scale, 0.15, Float(game.bus.position.z) * scale)

        // A little dust kicks up from under the bus while she rolls along (throttled).
        if !reduceMotion && moving > 0.55 {
            dustAccum += dt
            if dustAccum > 0.22 { dustAccum = 0; juice.burst(at: busGround, kind: .dust, count: 3) }
        } else {
            dustAccum = 0
        }
        cameraKick.step(toward: 0, dt: dt)

        // Lean into the current turn, only while actually rolling.
        var leanTarget = 0.0
        switch game.currentTurnCue {
        case .left:  leanTarget = -0.16 * moving
        case .right: leanTarget =  0.16 * moving
        default:     leanTarget = 0
        }
        lean = Easing.smoothed(lean, toward: reduceMotion ? 0 : leanTarget, rate: 5, dt: dt)

        // Squash when she slows hard / stops at a light; the spring bounces it back.
        if !reduceMotion {
            if prevDrivePrompt != .stop && game.drivePrompt == .stop {
                squash.nudge(3.0)
                juice.burst(at: busGround, kind: .dust, count: 9)   // brake puff
                cameraKick.nudge(1.6)
            } else {
                let decel = (prevSpeed - speed) / dt
                if decel > 30 { squash.nudge(min(decel, 120) * 0.02) }
            }
        }
        squash.step(toward: 0, dt: dt)

        // Breathe gently when parked; bounce on a fresh pickup or a honk.
        let bob = (!reduceMotion && speed < 1.0) ? 0.03 * sin(elapsed * 2.0) : 0.0
        if game.currentPassengerId != nil && prevPassengerId == nil && !reduceMotion {
            hop.nudge(3.5)
            juice.burst(at: busGround + [0, 1.3, 0], kind: .heart, count: 10)   // happy pickup
            cameraKick.nudge(2.4)
        }
        if honk && !reduceMotion { wiggle = 0.22; hop.nudge(1.5) }
        hop.step(toward: bob, dt: dt)
        wiggle = Easing.smoothed(wiggle, toward: 0, rate: 8, dt: dt)

        updateFace(game: game, dt: dt)

        prevSpeed = speed
        prevPassengerId = game.currentPassengerId
        prevDrivePrompt = game.drivePrompt
    }

    /// Blinks on a natural rhythm and eases the pupils toward whatever Amelia is
    /// heading for, so her eyes feel attentive rather than glassy.
    private func updateFace(game: GameSession, dt: Double) {
        guard let face else { return }

        if elapsed >= nextBlink {
            blinkUntil = elapsed + 0.12
            nextBlink = elapsed + Double.random(in: 2.2...5.0)
        }
        let blinking = elapsed < blinkUntil
        let eyeY: Float = blinking ? 0.12 : 1.0
        for eye in face.eyes { eye.scale = [1, eyeY, 1] }

        // Glance toward the current destination (bus faces +x; z is its left/right).
        var lateral = 0.0
        if !reduceMotion, let target = game.currentTarget {
            let dx = target.position.x - game.bus.position.x
            let dz = target.position.z - game.bus.position.z
            let bearing = atan2(dz, dx) - game.bus.heading
            lateral = max(-1.0, min(1.0, sin(bearing)))
        }
        lookX = Easing.smoothed(lookX, toward: lateral, rate: 6, dt: dt)
        lookY = Easing.smoothed(lookY, toward: 0, rate: 6, dt: dt)
        let amp: Float = 0.05
        for (i, pupil) in face.pupils.enumerated() {
            let rest = face.pupilRest[i]
            pupil.position = [rest.x, rest.y + Float(lookY) * amp, rest.z + Float(lookX) * amp]
        }
    }

    /// Places the ambient NPC friends at their home places, and the episode's
    /// rider waiting at the pickup stop — each rigged so it can come alive
    /// (idle-bob, blink, turn-to-watch, wave). Animated every frame in `step`.
    private func buildPassengers(session: AppSession, game: GameSession) {
        let plan = game.passengerPlan
        self.plan = plan

        for p in session.content.passengers where p.id != plan?.passengerId {
            guard let place = session.content.places.first(where: { $0.id == p.homePlace }) else { continue }
            let rig = ModelLibrary.characterRig(modelRef: p.modelRef,
                                                color: ModelLibrary.color(hex: p.color) ?? .gray)
            let home = groundPos(place.position.vec, offsetX: 1.8)
            rig.root.position = home
            root.addChild(rig.root)
            friends.append(CharacterActor(rig: rig, home: home, baseYaw: restYaw(at: home)))
        }

        guard let plan,
              let rp = session.content.passengers.first(where: { $0.id == plan.passengerId }) else { return }
        pickupPos = game.place(plan.pickupPlaceId)?.position.vec
        dropoffPos = game.place(plan.dropoffPlaceId)?.position.vec
        let rig = ModelLibrary.characterRig(modelRef: rp.modelRef,
                                            color: ModelLibrary.color(hex: rp.color) ?? .orange)
        let home = pickupPos.map { groundPos($0, offsetX: 1.2) } ?? [0, 0, 0]
        rig.root.position = home
        root.addChild(rig.root)
        riderActor = CharacterActor(rig: rig, home: home, baseYaw: restYaw(at: home))
    }

    /// A character's resting facing: turned roughly toward the neighborhood centre
    /// so the cast looks "in", until the passing bus pulls their gaze.
    private func restYaw(at home: SIMD3<Float>) -> Double {
        Double(atan2(-home.x, -home.z))
    }

    /// Updates the rider: waiting at the stop (with an excited hop as the bus pulls
    /// up), hidden while aboard, then standing at the drop-off — with a delighted
    /// hop the moment it's delivered, thrilled to be home.
    private func updateRider(game: GameSession, busPos: SIMD3<Float>, dt: Double, honk: Bool) {
        guard let actor = riderActor else { return }
        let aboard = game.currentPassengerId == plan?.passengerId
        if aboard {
            riderBoardedOnce = true
            actor.node.isEnabled = false
            return
        }
        if riderBoardedOnce {
            if !actor.node.isEnabled {            // first frame back: hop home, happy
                if let dropoffPos { actor.home = groundPos(dropoffPos, offsetX: 1.2) }
                actor.hop.nudge(reduceMotion ? 0 : 3.5)
                actor.node.isEnabled = true
            }
        } else {
            actor.node.isEnabled = true
            if !riderGreeted {                    // a one-time excited bounce on arrival
                let dx = busPos.x - actor.node.position.x, dz = busPos.z - actor.node.position.z
                if (dx * dx + dz * dz).squareRoot() < 2.6 {
                    riderGreeted = true
                    actor.hop.nudge(reduceMotion ? 0 : 2.5)
                }
            }
        }
        animateCharacter(actor, busPos: busPos, dt: dt, honk: honk)
    }

    /// Gives a character life from the bus's position: a gentle idle bob, a
    /// staggered blink, a turn-to-watch as the bus passes, a glance, and a wave
    /// hello when it's close. A honk gets an enthusiastic wave back + a hop.
    /// Eased/sprung so nothing snaps; Reduce-Motion aware.
    private func animateCharacter(_ a: CharacterActor, busPos: SIMD3<Float>, dt: Double, honk: Bool = false) {
        let dx = Double(busPos.x - a.home.x)
        let dz = Double(busPos.z - a.home.z)
        let dist = (dx * dx + dz * dz).squareRoot()
        let near = !reduceMotion && dist < 5.0

        // Honk! Friends in earshot wave back enthusiastically and give a happy hop.
        if honk && !reduceMotion && dist < 9.0 {
            a.wave = 1.0
            a.hop.nudge(2.5)
        }

        // Idle bob (gated by Reduce Motion) plus any delight hop from boarding/arrival.
        let bob = reduceMotion ? 0 : 0.035 * sin(elapsed * 2.2 + a.phase)
        a.hop.step(toward: 0, dt: dt)
        a.node.position = [a.home.x, a.home.y + Float(bob) + Float(a.hop.value), a.home.z]

        // Turn to watch the passing bus, else settle back to the resting facing.
        let targetYaw = near ? atan2(dx, dz) : a.baseYaw
        a.yaw = Easing.smoothed(a.yaw, toward: targetYaw, rate: 4, dt: dt)
        a.node.orientation = simd_quatf(angle: Float(a.yaw), axis: [0, 1, 0])

        // Blink on a natural, staggered rhythm (kept even under Reduce Motion).
        if elapsed >= a.nextBlink {
            a.blinkUntil = elapsed + 0.12
            a.nextBlink = elapsed + Double.random(in: 2.4...5.5)
        }
        let eyeY: Float = elapsed < a.blinkUntil ? 0.12 : 1.0
        for eye in a.face.eyes { eye.scale = [1, eyeY, 1] }

        // Glance toward the bus (eyes are children, so work in the head's frame).
        let lateral = near ? max(-1.0, min(1.0, sin(atan2(dx, dz) - a.yaw))) : 0.0
        a.look = Easing.smoothed(a.look, toward: lateral, rate: 6, dt: dt)
        for (i, pupil) in a.face.pupils.enumerated() {
            let r = a.face.pupilRest[i]
            pupil.position = [r.x + Float(a.look) * 0.03, r.y, r.z]
        }

        // Wave hello while the bus is close: raise the arm and flutter it.
        a.wave = Easing.smoothed(a.wave, toward: near ? 1.0 : 0.0, rate: 5, dt: dt)
        let raise = Float(a.wave) * 2.2
        let flutter = Float(a.wave) * 0.35 * Float(sin(elapsed * 9.0))
        a.waveArm.orientation = simd_quatf(angle: raise + flutter, axis: [0, 0, 1])
    }

    private func groundPos(_ v: Vec2, offsetX: Float = 0) -> SIMD3<Float> {
        [Float(v.x) * scale + offsetX, 0, Float(v.z) * scale]
    }

    /// Builds a floating balloon or spinning coin for each data-driven collectible.
    private func buildCollectibles(session: AppSession) {
        for c in session.content.collectibles {
            let color = ModelLibrary.color(hex: c.color)
            let node = c.kind == "coin"
                ? ModelLibrary.coin(color: color ?? .init(red: 1.0, green: 0.82, blue: 0.25, alpha: 1))
                : ModelLibrary.balloon(color: color ?? .init(red: 1.0, green: 0.37, blue: 0.48, alpha: 1))
            node.position = groundPos(c.position.vec)
            collectibleNodes.append((id: c.id, node: node))
            root.addChild(node)
        }
    }

    /// Bobs/spins the collectibles and removes any the bus has scooped.
    private func updateCollectibles(game: GameSession) {
        for entry in collectibleNodes where entry.node.isEnabled {
            if game.isCollected(entry.id) {
                if !reduceMotion { juice.burst(at: entry.node.position, kind: .sparkle, count: 10) }
                entry.node.isEnabled = false       // scooped — pop it out of the world
                continue
            }
            let bob = 0.12 * Float(sin(elapsed * 3.0 + Double(entry.node.position.x)))
            entry.node.position.y = 1.4 + bob
            entry.node.orientation = simd_quatf(angle: Float(elapsed * 1.5), axis: [0, 1, 0])
        }
    }

    /// The in-world "spot it" beat. While the game is waiting for a find answer,
    /// coloured balloons float ahead of the bus; the child steers to aim (the aimed
    /// balloon swells and bobs) and beeps the horn to pick it. Selection is driving,
    /// not a menu — so it works with the Siri Remote and every controller. The Core
    /// is untouched: this only reads `awaitingFind`/`findOptions` and calls back
    /// `answerFind` (a wrong beep is gently re-prompted, never punished).
    private func updateFindBeat(game: GameSession, steer: Double, pick: Bool) {
        guard game.awaitingFind else {
            if findActive { clearFindBalloons(); findActive = false }
            return
        }
        if !findActive {
            spawnFindBalloons(game.findOptions)
            findActive = true
        }
        let n = findBalloons.count
        guard n > 0 else { return }

        // Keep the balloons floating just ahead of the bus, in its facing.
        let p = game.bus.position
        findRig?.position = [Float(p.x) * scale, 0, Float(p.z) * scale]
        findRig?.orientation = simd_quatf(angle: Float(-game.bus.heading), axis: [0, 1, 0])

        // Aim with the steering axis: full-left → leftmost balloon, full-right →
        // rightmost. The aimed one swells and bobs so the child sees their choice.
        let s = max(-1.0, min(1.0, steer))
        findAimIndex = min(n - 1, max(0, Int((s + 1) / 2 * Double(n - 1) + 0.5)))
        for (i, entry) in findBalloons.enumerated() {
            let aimed = i == findAimIndex
            let bob = reduceMotion ? 0 : Float(sin(elapsed * 3.0 + Double(i))) * 0.12
            entry.node.position.y = 1.9 + bob + (aimed ? 0.35 : 0)
            let sc: Float = aimed ? 1.35 : 0.8
            entry.node.scale = [sc, sc, sc]
            if !reduceMotion {
                entry.node.orientation = simd_quatf(angle: Float(elapsed * (aimed ? 1.6 : 0.4)),
                                                    axis: [0, 1, 0])
            }
        }

        // Beep the horn (or click select) to choose the aimed balloon.
        if pick { game.answerFind(findBalloons[findAimIndex].id) }
    }

    /// Builds one floating balloon per find option, ordered left→right ahead of the
    /// bus. Colours come straight from the option data (the same ids the Core scores).
    private func spawnFindBalloons(_ options: [FindOption]) {
        clearFindBalloons()
        let rig = Entity()
        let n = options.count
        let spread: Float = 3.4
        for (i, opt) in options.enumerated() {
            let color = ModelLibrary.color(hex: opt.color) ?? .gray
            let balloon = ModelLibrary.balloon(color: color)
            let z = n > 1 ? (Float(i) / Float(n - 1) - 0.5) * 2 * spread : 0
            balloon.position = [4.4, 1.9, z]     // ahead (+x) of the bus, spread across
            rig.addChild(balloon)
            findBalloons.append((id: opt.id, node: balloon))
        }
        root.addChild(rig)
        findRig = rig
        findAimIndex = n / 2                      // default to the middle
    }

    /// Pops the find balloons out of the world (with a little sparkle when they were
    /// actually present — i.e. the child just answered correctly).
    private func clearFindBalloons() {
        if !reduceMotion {
            for entry in findBalloons { juice.burst(at: entry.node.position, kind: .sparkle, count: 6) }
        }
        findRig?.removeFromParent()
        findRig = nil
        findBalloons.removeAll()
    }

    private func updateBeacon(target: EpisodeTarget?) {
        guard let target else { beacon.isEnabled = false; return }
        beacon.isEnabled = true
        let bob = 0.2 * Float(sin(elapsed * 2.2))
        beacon.position = [Float(target.position.x) * scale, 1.6 + bob, Float(target.position.z) * scale]
    }

    private func publishHUD(_ game: GameSession) {
        let targetId = game.currentTarget?.kind == .place ? game.currentTarget?.id : nil
        var next = HUDModel()
        next.stars = game.save.stars
        next.collected = game.collectedCount
        next.subtitle = game.subtitle
        next.turnCue = game.currentTurnCue
        next.drivePrompt = game.drivePrompt
        next.destinationNameId = game.currentTargetNameId
        next.awaitingChoice = game.awaitingChoice
        next.awaitingFind = game.awaitingFind
        next.finished = game.finished
        next.rewardStars = game.rewardPlan?.stars ?? game.sparkleCount
        next.rewardStickerId = game.rewardPlan?.stickerId
        next.busX = game.bus.position.x
        next.busZ = game.bus.position.z
        next.busHeading = game.bus.heading
        next.targetX = game.currentTarget?.position.x
        next.targetZ = game.currentTarget?.position.z
        next.places = places.map {
            HUDPlace(id: $0.id, x: $0.position.x, z: $0.position.z,
                     colorHex: $0.beaconColor, isTarget: $0.id == targetId)
        }
        if next != hud { hud = next }
    }

    private func positionCamera() {
        let bp = bus.position
        camera.position = [bp.x - 6, bp.y + 4 + Float(cameraKick.value), bp.z + 6]
        camera.look(at: bp, from: camera.position, relativeTo: nil)
    }
}

#else

/// Fallback when RealityKit is unavailable (SDK older than tvOS 26).
struct DriveSpikeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("3D preview needs RealityKit (tvOS 26+).")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Button(session.string("ui.back")) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(80)
    }
}

#endif
