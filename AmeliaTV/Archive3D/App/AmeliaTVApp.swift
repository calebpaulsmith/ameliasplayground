import SwiftUI
import AmeliaCore

/// App entry point. Phase 1 wires the SwiftUI shell to the rendering-agnostic
/// GameCore and the input/render adapters. Gameplay screens (garage, full
/// episode) are Phase 2.
@main
struct AmeliaTVApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

/// App-wide state owned by the shell: the loaded content, the save, and the
/// chosen language. Pure-Swift Core types; no rendering deps here.
@MainActor
final class AppSession: ObservableObject {
    @Published var language: Language
    @Published var content: GameContent
    let saveStore: SaveStore
    @Published var save: SaveSlot

    init() {
        let store = SaveStore()
        let loaded = store.load()
        self.saveStore = store
        self.save = loaded
        self.language = loaded.language
        self.content = AppSession.loadBundledContent()
    }

    func setLanguage(_ lang: Language) {
        language = lang
        save.language = lang
        saveStore.save(save)
    }

    func string(_ id: String, vars: [String: String] = [:]) -> String {
        content.localizer.string(id, language, vars: vars)
    }

    /// Persist updated progress (called by the running episode session).
    func persist(_ slot: SaveSlot) {
        save = slot
        saveStore.save(slot)
    }

    /// Loads the data-driven content from the app bundle's Content/ folder.
    /// Falls back to empty content (never crashes) if something is missing.
    private static func loadBundledContent() -> GameContent {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Content"),
              let content = try? ContentLoader.load(from: dir) else {
            return GameContent()
        }
        return content
    }
}
