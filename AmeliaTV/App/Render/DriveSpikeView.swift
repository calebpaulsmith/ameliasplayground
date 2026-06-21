import SwiftUI
import AmeliaCore

#if canImport(RealityKit)
import RealityKit

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
    private var camera = Entity()
    private var beacon = Entity()
    private var neighborhood: NeighborhoodScene?
    private var timer: Timer?
    private var lastTick = Date()
    private var elapsed: Double = 0

    // The episode passenger ("rider") who waits at the stop, boards, then exits.
    private var rider = Entity()
    private var plan: GameSession.PassengerPlan?
    private var pickupPos: Vec2?
    private var dropoffPos: Vec2?
    private var riderBoardedOnce = false
    private var spokeReward = false   // speak Mom's praise once, when the episode ends

    // Collectibles (balloons / coins) scattered along the route; hidden once the
    // bus scoops them. Each entry keeps the collectible id so we can ask the game.
    private var collectibleNodes: [(id: String, node: Entity)] = []

    // A turn picked by an on-screen (touch) button, consumed on the next tick.
    // Lets the fork choice be made without a controller (e.g. on iPad).
    private var pendingTouchTurn: InputIntents.DiscreteTurn = .none

    /// Called by the HUD's on-screen LEFT/RIGHT buttons.
    func chooseTurn(_ turn: InputIntents.DiscreteTurn) { pendingTouchTurn = turn }

    /// Maps Game Core ground units to RealityKit meters for a couch-scale view.
    private let scale: Float = 0.12

    func makeRoot() -> Entity {
        bus = ModelLibrary.busEntity(placeholderColor: .init(red: 0.23, green: 0.63, blue: 1.0, alpha: 1))
        bus.position = [0, 0.55, 0]
        root.addChild(bus)

        // A bright floating pillar marking where to drive next. Hidden until the
        // episode sets a target; it bobs gently so a young child can spot it.
        beacon = ModelLibrary.placeholderBox(
            color: .init(red: 1.0, green: 0.82, blue: 0.25, alpha: 1),
            size: [0.25, 2.4, 0.25]
        )
        beacon.isEnabled = false
        root.addChild(beacon)

        let light = DirectionalLight()
        light.light.intensity = 4000
        light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0.4, 0])
        root.addChild(light)

        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 55
        camera = cam
        root.addChild(camera)

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

        // Build the data-driven neighborhood now that content is available, and
        // insert it beneath the already-rendered bus/beacon/camera.
        let scene = NeighborhoodScene(content: session.content, scale: scale)
        neighborhood = scene
        root.addChild(scene.root)

        buildPassengers(session: session, game: game)
        buildCollectibles(session: session)

        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
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
        game.tick(dt: dt, input: intents)

        // When the episode finishes, Mom praises the player once (reward screen).
        if game.finished && !spokeReward {
            spokeReward = true
            game.dialogue.play("reward.complete", force: true)
        }

        let p = game.bus.position
        bus.position = [Float(p.x) * scale, 0.55, Float(p.z) * scale]
        bus.orientation = simd_quatf(angle: Float(-game.bus.heading), axis: [0, 1, 0])

        // Engine hum rises and falls with how fast Amelia is rolling.
        audio.setEngineIntensity(abs(game.bus.speed) / game.core.assistLevel.maxSpeed)

        updateBeacon(target: game.currentTarget)
        updateRider(game: game)
        updateCollectibles(game: game)
        let states = Dictionary(uniqueKeysWithValues: game.lightSnapshot().map { ($0.id, $0.state) })
        neighborhood?.updateLights(states)
        positionCamera()
        publishHUD(game)
    }

    /// Places the ambient NPC friends at their home places, and the episode's
    /// rider waiting at the pickup stop. The rider is animated in `step`.
    private func buildPassengers(session: AppSession, game: GameSession) {
        let plan = game.passengerPlan
        self.plan = plan

        for p in session.content.passengers where p.id != plan?.passengerId {
            guard let place = session.content.places.first(where: { $0.id == p.homePlace }) else { continue }
            let npc = ModelLibrary.character(color: ModelLibrary.color(hex: p.color) ?? .gray)
            npc.position = groundPos(place.position.vec, offsetX: 1.8)
            root.addChild(npc)
        }

        guard let plan,
              let rp = session.content.passengers.first(where: { $0.id == plan.passengerId }) else { return }
        pickupPos = game.place(plan.pickupPlaceId)?.position.vec
        dropoffPos = game.place(plan.dropoffPlaceId)?.position.vec
        rider = ModelLibrary.character(color: ModelLibrary.color(hex: rp.color) ?? .orange)
        if let pickupPos { rider.position = groundPos(pickupPos, offsetX: 1.2) }
        root.addChild(rider)
    }

    /// Updates the rider: waiting at the stop, hidden while aboard, then standing
    /// at the drop-off once delivered.
    private func updateRider(game: GameSession) {
        guard plan != nil else { return }
        let aboard = game.currentPassengerId == plan?.passengerId
        if aboard {
            riderBoardedOnce = true
            rider.isEnabled = false
        } else if riderBoardedOnce {
            rider.isEnabled = true
            if let dropoffPos { rider.position = groundPos(dropoffPos, offsetX: 1.2) }
        } else {
            rider.isEnabled = true
        }
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
                entry.node.isEnabled = false       // scooped — pop it out of the world
                continue
            }
            let bob = 0.12 * Float(sin(elapsed * 3.0 + Double(entry.node.position.x)))
            entry.node.position.y = 1.4 + bob
            entry.node.orientation = simd_quatf(angle: Float(elapsed * 1.5), axis: [0, 1, 0])
        }
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
        camera.position = [bp.x - 6, bp.y + 4, bp.z + 6]
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
