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

            HUDView(model: engine.hud)
                .environmentObject(session)

            Button(session.string("ui.back")) { dismiss() }
                .buttonStyle(.bordered)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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

    /// Maps Game Core ground units to RealityKit meters for a couch-scale view.
    private let scale: Float = 0.12

    func makeRoot() -> Entity {
        bus = ModelLibrary.entity(
            id: "bus",
            placeholderColor: .init(red: 0.23, green: 0.63, blue: 1.0, alpha: 1),
            size: [1.6, 1.1, 0.9]
        )
        addFriendlyFace(to: bus)
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

    /// Gives the placeholder bus two big friendly eyes so it reads as a character
    /// — the cozy "friendly vehicle" genre vibe, in original geometry (D-IP-1).
    /// The bus's forward axis is local +x (see the heading rotation in `step`).
    private func addFriendlyFace(to bus: Entity) {
        for z in [Float(-0.24), 0.24] {
            let white = ModelLibrary.sphere(radius: 0.17, color: .white)
            white.position = [0.78, 0.18, z]
            bus.addChild(white)
            let pupil = ModelLibrary.sphere(radius: 0.075,
                color: .init(red: 0.1, green: 0.12, blue: 0.16, alpha: 1))
            pupil.position = [0.9, 0.18, z]
            bus.addChild(pupil)
        }
    }

    func start(session: AppSession) {
        let game = GameSession(
            content: session.content,
            save: session.save,
            speaker: speaker,
            persist: { [weak session] slot in
                Task { @MainActor in session?.persist(slot) }
            }
        )
        game.language = session.language
        game.start(episodeId: "first-day")
        self.game = game
        self.places = session.content.places

        // Build the data-driven neighborhood now that content is available, and
        // insert it beneath the already-rendered bus/beacon/camera.
        let scene = NeighborhoodScene(content: session.content, scale: scale)
        neighborhood = scene
        root.addChild(scene.root)

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
    }

    private func step() {
        guard let game else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 1.0 / 20.0)
        lastTick = now
        elapsed += dt

        game.tick(dt: dt, input: input.currentIntents())

        let p = game.bus.position
        bus.position = [Float(p.x) * scale, 0.55, Float(p.z) * scale]
        bus.orientation = simd_quatf(angle: Float(-game.bus.heading), axis: [0, 1, 0])

        updateBeacon(target: game.currentTarget)
        let states = Dictionary(uniqueKeysWithValues: game.lightSnapshot().map { ($0.id, $0.state) })
        neighborhood?.updateLights(states)
        positionCamera()
        publishHUD(game)
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
        next.subtitle = game.subtitle
        next.turnCue = game.currentTurnCue
        next.drivePrompt = game.drivePrompt
        next.destinationNameId = game.currentTargetNameId
        next.finished = game.finished
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
