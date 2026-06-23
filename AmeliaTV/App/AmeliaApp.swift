import SwiftUI
import SpriteKit

/// App entry point for the 2D top-down GTA-style town.
///
/// The old RealityKit 3D app is preserved under `Archive3D/` (not compiled).
@main
struct AmeliaApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
        }
    }
}

struct GameView: View {
    @State private var controls = DriveControls()
    // Created once per view identity; a fixed 16:9 canvas scaled to fit.
    @State private var scene = TownScene(size: CGSize(width: 1920, height: 1080))

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()
            #if os(iOS)
            // Touch controls only on iPhone/iPad. tvOS drives via the Siri Remote
            // / a game controller, so its screen stays clean.
            TouchControlsView(controls: controls)
            #endif
        }
        .onAppear { scene.controls = controls }
    }
}

#if os(iOS)
/// On-screen driving controls for touch devices, pinned to the bottom corners so
/// the middle of the screen — where the bus and the action are — stays clear.
struct TouchControlsView: View {
    let controls: DriveControls

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                HStack(spacing: 22) {
                    HoldButton(system: "arrowtriangle.left.fill",
                               onDown: { controls.setSteer(-1) }, onUp: { controls.setSteer(0) })
                    HoldButton(system: "arrowtriangle.right.fill",
                               onDown: { controls.setSteer(1) }, onUp: { controls.setSteer(0) })
                }
                Spacer()
                HStack(spacing: 22) {
                    HoldButton(system: "hand.raised.fill", tint: .red.opacity(0.85),
                               onDown: { controls.setBraking(true) }, onUp: { controls.setBraking(false) })
                    HoldButton(system: "speaker.wave.2.fill", tint: .blue.opacity(0.85),
                               onDown: { controls.requestHonk() }, onUp: {})
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }
}

/// A press-and-hold button (standard Buttons only fire on release).
struct HoldButton: View {
    let system: String
    var tint: Color = .black.opacity(0.4)
    let onDown: () -> Void
    let onUp: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: system)
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 96, height: 96)
            .background(Circle().fill(tint).opacity(pressed ? 1.0 : 0.75))
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 3))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true; onDown() } }
                    .onEnded { _ in pressed = false; onUp() }
            )
    }
}
#endif
