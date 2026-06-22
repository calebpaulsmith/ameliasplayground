import SwiftUI
import AmeliaCore

/// The title screen. One clear path forward: a big, pre-focused "Let's go!" that
/// drops straight into the garage — no language wall in front of a young child
/// (the game starts in English; Spanish lives in Settings). A small Settings
/// button is the only secondary affordance.
struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showingGarage = false
    @State private var showingSettings = false
    @State private var showingDriveDirect = false
    @State private var showingDialoguePreview = false
    @FocusState private var goFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.82, blue: 0.96),
                         Color(red: 0.95, green: 0.97, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Text("Amelia")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.81))

                Text(session.string("title.tagline"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    showingGarage = true
                } label: {
                    Text(session.string("ui.letsGo"))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .frame(minWidth: 420, minHeight: 92)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.43, blue: 0.81))
                .focused($goFocused)

                Button {
                    showingSettings = true
                } label: {
                    Label(session.string("ui.settings"), systemImage: "gearshape.fill")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
            .padding(80)
            .adaptiveTVCanvas()
        }
        // Land the remote on the big "Let's go!" so a child can start immediately.
        .defaultFocus($goFocused, true)
        .onAppear {
            goFocused = true
            jumpToScreenshotScreenIfRequested()
        }
        .fullScreenCover(isPresented: $showingGarage) {
            GarageView()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showingDriveDirect) {
            DriveSpikeView()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showingDialoguePreview) {
            // CI-only: a static frame proving the dialogue portrait bubble renders,
            // independent of in-play timing.
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.96),
                                        Color(red: 0.86, green: 0.93, blue: 0.86)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                HUDView(model: HUDModel(
                    subtitle: session.string("m.goStop"),
                    speakerName: session.string("mom.name"),
                    speakerColorHex: "#2ea59e"))
                    .environmentObject(session)
            }
        }
    }

    /// CI-only deep link: when `SCREENSHOT_SCREEN` is set (by the screenshot
    /// workflow), jump straight to that screen so it can be captured. A no-op in
    /// normal play (the variable is never set).
    private func jumpToScreenshotScreenIfRequested() {
        switch ProcessInfo.processInfo.environment["SCREENSHOT_SCREEN"] {
        case "garage":   showingGarage = true
        case "drive":    showingDriveDirect = true
        case "dialogue": showingDialoguePreview = true
        case "settings": showingSettings = true
        default:         break
        }
    }
}
