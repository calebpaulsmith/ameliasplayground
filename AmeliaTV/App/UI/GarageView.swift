import SwiftUI
import AmeliaCore

#if canImport(RealityKit)
import RealityKit

/// A2-07 — the cozy home garage where the day begins. Mechanic Mom greets the
/// player (TTS, bilingual), a sticker wall shows what's been earned, and one big
/// "Let's go!" starts the adventure. Original placeholder art (D-IP-1); USDZ can
/// be swapped in by id later.
struct GarageView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = GarageEngine()
    @State private var showingDrive = false
    @FocusState private var goFocused: Bool

    var body: some View {
        ZStack {
            RealityView { content in
                content.add(engine.makeRoot())
            }
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    Button(session.string("ui.back")) { dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    StickerWall(title: session.string("garage.stickers"),
                                earned: session.save.stickers)
                }
                Spacer()
                if !engine.subtitle.isEmpty {
                    Text(engine.subtitle)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                        .padding(26)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
                Button {
                    engine.stop()
                    showingDrive = true
                } label: {
                    Text(session.string("ui.letsGo"))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .frame(minWidth: 420, minHeight: 92)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.43, blue: 0.81))
                .padding(.top, 24)
                .focused($goFocused)
            }
            .padding(56)
            .adaptiveTVCanvas()
        }
        // Pre-focus the big "Let's go!" so the remote can start the drive at once,
        // instead of landing on the small "Back" button (or nowhere) over the scene.
        .defaultFocus($goFocused, true)
        .onAppear {
            engine.start(session: session)
            goFocused = true
        }
        .onDisappear { engine.stop() }
        .fullScreenCover(isPresented: $showingDrive, onDismiss: { engine.start(session: session) }) {
            DriveSpikeView().environmentObject(session)
        }
    }
}

/// Owns the static garage scene and Mom's greeting. A light idle bob keeps the
/// bus feeling alive while Mom talks.
@MainActor
final class GarageEngine: ObservableObject {
    @Published var subtitle: String = ""

    private let speaker = SpeechSpeaker()
    private let audio = ProceduralAudio()
    private let root = Entity()
    private var bus = Entity()
    private var mom = Entity()
    private var timer: Timer?
    private var elapsed: Double = 0
    private var didGreet = false
    private var didBuildFriends = false

    func makeRoot() -> Entity {
        let floor = ModelLibrary.ground(size: 16,
            color: .init(red: 0.78, green: 0.80, blue: 0.84, alpha: 1))
        root.addChild(floor)

        let backWall = ModelLibrary.placeholderBox(
            color: .init(red: 0.60, green: 0.80, blue: 0.92, alpha: 1), size: [14, 5, 0.4])
        backWall.position = [0, 2.5, -3.2]
        root.addChild(backWall)

        // A repair lift with the bus raised on it.
        let lift = ModelLibrary.placeholderBox(
            color: .init(red: 0.45, green: 0.47, blue: 0.52, alpha: 1), size: [3.6, 0.5, 2.6])
        lift.position = [0, 0.25, 0]
        root.addChild(lift)

        bus = ModelLibrary.busEntity(placeholderColor: .init(red: 0.23, green: 0.63, blue: 1.0, alpha: 1))
        // Turn the bus so its friendly face (+x) looks toward the camera (+z).
        bus.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        bus.position = [0, 1.1, 0]
        root.addChild(bus)

        // Mechanic Mom, beside the bus, with a little wrench.
        mom = ModelLibrary.character(modelRef: "mom", color: .init(red: 0.18, green: 0.66, blue: 0.62, alpha: 1))
        mom.position = [2.4, 0, 0.6]
        let wrench = ModelLibrary.placeholderBox(
            color: .init(white: 0.85, alpha: 1), size: [0.1, 0.5, 0.1])
        wrench.position = [2.0, 0.5, 0.9]
        wrench.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])
        root.addChild(mom)
        root.addChild(wrench)

        // A red toolbox on the floor.
        let toolbox = ModelLibrary.placeholderBox(
            color: .init(red: 0.86, green: 0.30, blue: 0.28, alpha: 1), size: [0.8, 0.5, 0.5])
        toolbox.position = [3.4, 0.25, 1.2]
        root.addChild(toolbox)

        let key = DirectionalLight()
        key.light.intensity = 4200
        key.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0.5, 0])
        root.addChild(key)

        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 52
        cam.position = [0.6, 2.6, 6.6]
        cam.look(at: [0, 1.1, 0], from: cam.position, relativeTo: nil)
        root.addChild(cam)

        return root
    }

    func start(session: AppSession) {
        subtitle = session.string("garage.welcome")
        audio.setMusic(.garage)
        speaker.isEnabled = (UserDefaults.standard.object(forKey: "voiceEnabled") as? Bool) ?? true
        if !didGreet {
            didGreet = true
            speaker.speak(subtitle, language: session.language)
        }
        if !didBuildFriends {
            didBuildFriends = true
            buildRescueFriends(session.content)
        }
        elapsed = 0
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
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

    /// Parks the Rescue Team members who live at the garage beside the lift, so
    /// the player meets a couple of friends before setting off.
    private func buildRescueFriends(_ content: GameContent) {
        let here = content.vehicles.filter { $0.homePlace == "garage" }
        for (i, v) in here.enumerated() {
            let color = ModelLibrary.color(hex: v.color) ?? .init(white: 0.8, alpha: 1)
            let node = ModelLibrary.vehicle(modelRef: v.modelRef, role: v.role, color: color)
            node.position = [-3.2, 0, Float(i) * 2.4 - 1.0]
            node.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])  // face the camera
            root.addChild(node)
        }
    }

    private func tick() {
        elapsed += 1.0 / 60.0
        bus.position.y = 1.1 + 0.03 * Float(sin(elapsed * 2.0))   // gentle idle bob
    }
}

/// A small panel showing earned stickers, with a few empty slots so there's
/// always something to fill in. Placeholder for the full sticker book.
private struct StickerWall: View {
    let title: String
    let earned: [String]

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            HStack(spacing: 12) {
                ForEach(earned, id: \.self) { _ in
                    slot(filled: true)
                }
                ForEach(0..<max(0, 4 - earned.count), id: \.self) { _ in
                    slot(filled: false)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func slot(filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(filled ? Color(red: 1.0, green: 0.82, blue: 0.25).opacity(0.9) : .clear)
            .frame(width: 56, height: 56)
            .overlay {
                if filled {
                    Image(systemName: "star.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 3, dash: [6]))
                }
            }
    }
}

#else

/// Fallback when RealityKit is unavailable (SDK older than tvOS 26).
struct GarageView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var showingDrive = false
    @FocusState private var goFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Text(session.string("garage.welcome"))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Button(session.string("ui.letsGo")) { showingDrive = true }
                .buttonStyle(.borderedProminent)
                .focused($goFocused)
            Button(session.string("ui.back")) { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(80)
        .adaptiveTVCanvas()
        .defaultFocus($goFocused, true)
        .onAppear { goFocused = true }
        .fullScreenCover(isPresented: $showingDrive) {
            DriveSpikeView().environmentObject(session)
        }
    }
}

#endif
