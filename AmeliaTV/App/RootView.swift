import SwiftUI
import AmeliaCore

/// Phase 1 shell: a friendly title, a big language choice, and a button into the
/// rendering/input spike. This is intentionally minimal — the splash/garage/
/// adventure-board UI is Phase 2 (A2-07, A2-11).
struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showingGarage = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.82, blue: 0.96),
                         Color(red: 0.95, green: 0.97, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 48) {
                Text("Amelia")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.81))

                Text(session.string("lang.choose"))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 32) {
                    ForEach(Language.allCases, id: \.self) { lang in
                        Button {
                            session.setLanguage(lang)
                        } label: {
                            Text(lang.displayName)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .frame(minWidth: 240)
                                .padding(.vertical, 8)
                                .overlay(alignment: .bottom) {
                                    if session.language == lang {
                                        Capsule().frame(height: 6)
                                            .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.81))
                                    }
                                }
                        }
                        .buttonStyle(.card)
                    }
                }

                Button {
                    showingGarage = true
                } label: {
                    Text(session.string("ui.letsGo"))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .frame(minWidth: 360, minHeight: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.43, blue: 0.81))
            }
            .padding(80)
        }
        .fullScreenCover(isPresented: $showingGarage) {
            GarageView()
                .environmentObject(session)
        }
    }
}
