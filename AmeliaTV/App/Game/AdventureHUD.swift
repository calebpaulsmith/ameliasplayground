import SwiftUI
import AmeliaCore

/// Observable HUD state the SpriteKit `TownScene` writes and SwiftUI reads. Keeps
/// the scene free of SwiftUI layout while giving the player a single-glance
/// objective, a star count, and the current spoken line — so the story reads
/// even with the voice off (the no-reading / readable-UI constraint).
///
/// Not `@MainActor`-isolated: the scene updates it from SpriteKit's `update(_:)`,
/// which already runs on the main thread, so the published changes reach SwiftUI
/// on main without crossing an actor boundary.
final class AdventureHUD: ObservableObject {
    /// Big, plain-language goal — "Pick up Pip at the bus stop".
    @Published var objective: String = ""
    /// Stars earned this ride.
    @Published var stars: Int = 0
    /// Who is talking (Mom / Pip) and what they're saying, for the subtitle bar.
    @Published var speakerName: String = ""
    @Published var subtitle: String = ""
    /// Speaker accent colour (hex), so the bubble matches the character.
    @Published var speakerColorHex: String = "#2ea59e"
}

/// The on-screen HUD: an objective pill (top-left), a star counter (top-right),
/// and a character subtitle bar (bottom). Drawn over the SpriteKit scene and
/// non-interactive so it never steals focus or touches.
struct AdventureHUDView: View {
    @ObservedObject var hud: AdventureHUD

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                if !hud.objective.isEmpty {
                    Label(hud.objective, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                        .transition(.opacity)
                        .id(hud.objective)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "star.fill").foregroundColor(.yellow)
                    Text("\(hud.stars)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 2))
            }

            Spacer()

            if !hud.subtitle.isEmpty {
                VStack(spacing: 4) {
                    if !hud.speakerName.isEmpty {
                        Text(hud.speakerName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: hud.speakerColorHex) ?? .teal)
                    }
                    Text(hud.subtitle)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.6), lineWidth: 2))
                .padding(.bottom, 8)
                .transition(.opacity)
                .id(hud.subtitle)
            }
        }
        .padding(40)
        .animation(.easeInOut(duration: 0.25), value: hud.objective)
        .animation(.easeInOut(duration: 0.25), value: hud.subtitle)
        .allowsHitTesting(false)
    }
}

private extension Color {
    /// Parse a "#rrggbb" hex string. Returns nil if it doesn't look like one.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255,
                  opacity: 1)
    }
}
