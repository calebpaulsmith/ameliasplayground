import SwiftUI
import SpriteKit

/// App entry point for the 2D top-down adventure (the SpriteKit pivot).
///
/// The old RealityKit 3D app is preserved under `Archive3D/` (not compiled).
/// This slice shows one walkable room; everything else builds on top of it,
/// verified on video by CI before we trust it.
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
    // Created once per view identity; a fixed 16:9 canvas scaled to fit the TV.
    @State private var scene = RoomScene(size: CGSize(width: 1920, height: 1080))

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
