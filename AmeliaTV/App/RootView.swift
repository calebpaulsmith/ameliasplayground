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
        .onAppear { goFocused = true }
        .fullScreenCover(isPresented: $showingGarage) {
            GarageView()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(session)
        }
    }
}
