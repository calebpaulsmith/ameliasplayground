import SwiftUI
import AmeliaCore

/// Settings, kept deliberately tiny: the only choice a grown-up needs here is the
/// language. The game starts in English; this is where you switch to Spanish.
/// The choice is persisted immediately (local-only — privacy is a hard constraint).
struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @FocusState private var doneFocused: Bool
    // Narration is an optional aid — the game reads from the graphics/HUD alone.
    @AppStorage("voiceEnabled") private var voiceEnabled = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.82, blue: 0.96),
                         Color(red: 0.95, green: 0.97, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 48) {
                Text(session.string("settings.title"))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.81))

                VStack(spacing: 20) {
                    Text(session.string("settings.language"))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
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
                            #if os(tvOS)
                            .buttonStyle(.card)        // tvOS focus-aware card style
                            #else
                            .buttonStyle(.bordered)    // iPad/iOS: tappable bordered button
                            #endif
                        }
                    }
                }

                VStack(spacing: 20) {
                    Text(session.string("settings.voice"))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 32) {
                        ForEach([true, false], id: \.self) { on in
                            Button {
                                voiceEnabled = on
                            } label: {
                                Text(session.string(on ? "settings.voiceOn" : "settings.voiceOff"))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .frame(minWidth: 200)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) {
                                        if voiceEnabled == on {
                                            Capsule().frame(height: 6)
                                                .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.81))
                                        }
                                    }
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.bordered)
                            #endif
                        }
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text(session.string("ui.close"))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .frame(minWidth: 320, minHeight: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.43, blue: 0.81))
                .focused($doneFocused)
            }
            .padding(80)
            .adaptiveTVCanvas()
        }
        .onAppear { doneFocused = true }
    }
}
