import SwiftUI
import AmeliaCore

#if canImport(RealityKit)
import RealityKit

/// Phase 2 playable view: runs the "First Day" episode through `GameSession` and
/// renders it with RealityKit — a placeholder bus auto-drives the route, speaks
/// (AVSpeech), and shows a subtitle + star count. Art is placeholder; the full
/// neighborhood scene, HUD arrows, garage and reward screens are the next steps.
///
/// Requires the tvOS 26 SDK (RealityKit on tvOS); a SwiftUI fallback compiles on
/// older SDKs so the project always builds.
struct DriveSpikeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = SpikeEngine()

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.add(engine.makeRoot())
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("⭐️ \(engine.stars)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                if !engine.subtitle.isEmpty {
                    Text(engine.subtitle)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 760, alignment: .leading)
                }
                if engine.finished {
                    Text(session.string("reward.complete"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.81))
                }
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(40)

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
    @Published var subtitle: String = ""
    @Published var stars: Int = 0
    @Published var finished: Bool = false

    private let input = GameControllerInput()
    private let speaker = SpeechSpeaker()
    private var game: GameSession?

    private let root = Entity()
    private var bus = Entity()
    private var camera = Entity()
    private var timer: Timer?
    private var lastTick = Date()

    /// Maps Game Core ground units to RealityKit meters for a couch-scale view.
    private let scale: Float = 0.12

    func makeRoot() -> Entity {
        let ground = ModelLibrary.ground(size: 80, color: .init(red: 0.46, green: 0.78, blue: 0.42, alpha: 1))
        root.addChild(ground)

        bus = ModelLibrary.entity(
            id: "bus",
            placeholderColor: .init(red: 0.23, green: 0.63, blue: 1.0, alpha: 1),
            size: [1.6, 1.1, 0.9]
        )
        bus.position = [0, 0.55, 0]
        root.addChild(bus)

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
            persist: { [weak session] slot in
                Task { @MainActor in session?.persist(slot) }
            }
        )
        game.language = session.language
        game.start(episodeId: "first-day")
        self.game = game

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

        game.tick(dt: dt, input: input.currentIntents())

        let p = game.bus.position
        bus.position = [Float(p.x) * scale, 0.55, Float(p.z) * scale]
        bus.orientation = simd_quatf(angle: Float(-game.bus.heading), axis: [0, 1, 0])
        positionCamera()

        subtitle = game.subtitle
        stars = game.save.stars
        finished = game.finished
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
