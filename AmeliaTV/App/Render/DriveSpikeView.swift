import SwiftUI
import AmeliaCore

#if canImport(RealityKit)
import RealityKit

/// Phase 1 rendering + input spike (F1-04 / F1-05 / F1-06): renders a placeholder
/// bus on a ground plane with a follow camera, driven by the rendering-agnostic
/// `GameCore`, fed by `GameControllerInput` (Siri Remote or controller). This is
/// the de-risking spike for R-ENG-1, NOT the real game scene.
///
/// Requires the tvOS 26 SDK (RealityKit on tvOS). On older SDKs a SwiftUI
/// fallback is compiled instead (see the `#else` branch) so the foundation still
/// builds — the real RealityKit validation runs on CI with Xcode 26.
struct DriveSpikeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = SpikeEngine()

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                // Let RealityView infer its content type; we only add the root.
                content.add(engine.makeRoot())
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(session.string("ui.go") + " / " + session.string("ui.stop"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Spike: \(engine.assistDescription)")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(40)

            Button(session.string("ui.back")) { dismiss() }
                .buttonStyle(.bordered)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .onAppear { engine.start(language: session.language) }
        .onDisappear { engine.stop() }
    }
}

/// Owns the GameCore, the RealityKit entities, and the per-frame loop for the
/// spike. Kept out of SwiftUI so it can mutate entity transforms directly each
/// tick without triggering view rebuilds.
@MainActor
final class SpikeEngine: ObservableObject {
    private let core = GameCore()
    private let input = GameControllerInput()

    private let root = Entity()
    private var bus = Entity()
    private var camera = Entity()
    private var timer: Timer?
    private var lastTick = Date()

    /// Maps Game Core ground units to RealityKit meters for a couch-scale view.
    private let scale: Float = 0.12

    var assistDescription: String { core.assistLevel.rawValue }

    /// Builds (once) and returns the scene root for the RealityView to add.
    func makeRoot() -> Entity {
        // Ground.
        let ground = ModelLibrary.ground(size: 60, color: .init(red: 0.46, green: 0.78, blue: 0.42, alpha: 1))
        ground.position = [0, 0, 0]
        root.addChild(ground)

        // Placeholder bus (swapped for "bus.usdz" automatically if present).
        bus = ModelLibrary.entity(
            id: "bus",
            placeholderColor: .init(red: 0.23, green: 0.63, blue: 1.0, alpha: 1),
            size: [1.6, 1.1, 0.9]
        )
        bus.position = [0, 0.55, 0]
        root.addChild(bus)

        // Light.
        let light = DirectionalLight()
        light.light.intensity = 4000
        light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0.4, 0])
        root.addChild(light)

        // Camera (tvOS has no AR camera; we provide our own).
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 55
        camera = cam
        root.addChild(camera)

        positionCamera()
        return root
    }

    func start(language: Language) {
        core.assistLevel = AssistLevel.recommended(for: input.activeDevice)
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
    }

    private func step() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 1.0 / 20.0)
        lastTick = now

        // Keep assist in step with whatever device is active.
        core.assistLevel = AssistLevel.recommended(for: input.activeDevice)
        let intents = input.currentIntents()
        core.tick(dt: dt, input: intents)

        // Map Core (x, z, heading) to the RealityKit transform.
        let p = core.bus.position
        bus.position = [Float(p.x) * scale, 0.55, Float(p.z) * scale]
        bus.orientation = simd_quatf(angle: Float(-core.bus.heading), axis: [0, 1, 0])
        positionCamera()
    }

    private func positionCamera() {
        // Chase camera: behind and above the bus, looking at it.
        let bp = bus.position
        let behind: Float = 6
        let height: Float = 4
        camera.position = [bp.x - behind, bp.y + height, bp.z + behind]
        camera.look(at: bp, from: camera.position, relativeTo: nil)
    }
}

#else

/// Fallback when RealityKit is unavailable (SDK older than tvOS 26). Keeps the
/// app buildable; the 3D spike is exercised on CI with the tvOS 26 SDK.
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
