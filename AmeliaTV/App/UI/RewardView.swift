import SwiftUI
import AmeliaCore

/// A2-12 — the celebration that ends an episode: Mom's praise, the stars earned,
/// and the new sticker revealed with a little fanfare, then one big button back to
/// the garage (where the sticker now lives on the wall).
///
/// It's a full-screen, couch-readable takeover in the cozy original style: a warm
/// glow, gentle confetti, stars that pop in one by one, and a sticker "unlock"
/// card that flips in with a sweeping shine — the satisfying *you-earned-this*
/// beat, kept soft and friendly (never loud or harsh). Pure SwiftUI, no art
/// assets: every element is drawn, so it ships today and a real sticker image can
/// be swapped in later behind the same id. Honors Reduce Motion.
struct RewardView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Stars the episode awarded (from `GameSession.rewardPlan`).
    let stars: Int
    /// The sticker just earned, if any.
    let stickerId: String?
    /// "Back to the garage" — hands control back to the presenter.
    var onContinue: () -> Void = {}

    @State private var appear = false

    private var stickerName: String {
        guard let id = stickerId else { return "" }
        let s = session.string("sticker.\(id)")
        return s == "sticker.\(id)" ? "" : s     // localizer returns the id when missing
    }

    var body: some View {
        ZStack {
            Backdrop(animate: !reduceMotion, appear: appear)

            if !reduceMotion {
                Confetti(count: 44, palette: RewardPalette.confetti)
                    .opacity(appear ? 1 : 0)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 30) {
                headline
                praise

                StarsRow(count: max(stars, 1), shown: appear)
                    .padding(.top, 4)

                if stickerId != nil {
                    StickerReveal(stickerId: stickerId,
                                  title: session.string("reward.newSticker"),
                                  name: stickerName,
                                  animate: !reduceMotion,
                                  shown: appear)
                }

                ContinueButton(title: session.string("ui.backToGarage"),
                               animate: !reduceMotion,
                               action: onContinue)
                    .padding(.top, 8)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 28)
                    .animation(.easeOut(duration: 0.4).delay(reduceMotion ? 0.1 : 1.7), value: appear)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
            .frame(maxWidth: 1000)
            .background(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.15)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            )
            .scaleEffect(appear ? 1 : 0.86)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.78), value: appear)
        }
        .ignoresSafeArea()
        .onAppear { appear = true }
    }

    private var headline: some View {
        Text(session.string("reward.greatDriving"))
            .font(.system(size: 64, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: RewardPalette.gold,
                               startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: RewardPalette.gold[0].opacity(0.5), radius: 12, y: 4)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
    }

    private var praise: some View {
        Text(session.string("reward.complete"))
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 760)
    }
}

// MARK: - Palette

private enum RewardPalette {
    static let gold = [Color(red: 1.0, green: 0.86, blue: 0.36),
                       Color(red: 1.0, green: 0.66, blue: 0.22)]
    static let sky = Color(red: 0.36, green: 0.74, blue: 1.0)
    static let deepBlue = Color(red: 0.12, green: 0.43, blue: 0.81)
    static let confetti = [
        Color(red: 1.0, green: 0.82, blue: 0.25),
        Color(red: 0.20, green: 0.72, blue: 0.36),
        Color(red: 0.36, green: 0.74, blue: 1.0),
        Color(red: 0.95, green: 0.42, blue: 0.40),
        Color(red: 0.18, green: 0.78, blue: 0.72),
        Color(red: 0.78, green: 0.55, blue: 0.95)
    ]
}

// MARK: - Backdrop (warm glow + slow sunburst + vignette)

private struct Backdrop: View {
    let animate: Bool
    let appear: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            // Dim the scene and wash it in a warm, cozy light.
            LinearGradient(colors: [Color(red: 1.0, green: 0.80, blue: 0.55).opacity(0.55),
                                    Color(red: 0.10, green: 0.16, blue: 0.32).opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)

            // Soft radiating rays behind the card — the "reward" shine.
            Sunburst()
                .opacity(appear ? (animate ? 0.45 : 0.3) : 0)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(animate ? .linear(duration: 60).repeatForever(autoreverses: false) : nil, value: spin)
                .blur(radius: 12)
                .animation(.easeOut(duration: 0.8), value: appear)

            // Gentle vignette to focus the eye on the centre.
            RadialGradient(colors: [.clear, .black.opacity(0.45)],
                           center: .center, startRadius: 320, endRadius: 1100)
        }
        .onAppear { spin = true }
    }
}

private struct Sunburst: View {
    var body: some View {
        GeometryReader { geo in
            let n = 16
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    Capsule()
                        .fill(RewardPalette.gold[0].opacity(0.18))
                        .frame(width: 70, height: max(geo.size.width, geo.size.height) * 1.4)
                        .rotationEffect(.degrees(Double(i) / Double(n) * 360))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Confetti (Canvas-drawn, continuous, deterministic)

private struct Confetti: View {
    let count: Int
    let palette: [Color]
    private let pieces: [Piece]

    init(count: Int, palette: [Color]) {
        self.count = count
        self.palette = palette
        var rng = SeededGen(seed: 0xA1E11A)
        pieces = (0..<count).map { _ in Piece(using: &rng, palette: palette) }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for p in pieces {
                        let span = size.height + 120
                        let prog = (t * p.speed + p.phase).truncatingRemainder(dividingBy: 1)
                        let y = prog * span - 60
                        let x = p.x * size.width + sin((t + p.phase * 6) * p.sway) * 26
                        // Fade in at the top, out near the bottom.
                        let fade = min(1, min(prog * 6, (1 - prog) * 6))

                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(t * p.spin + p.phase * 6))
                        let rect = CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)
                        c.fill(Path(roundedRect: rect, cornerRadius: 2.5),
                               with: .color(p.color.opacity(0.9 * fade)))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private struct Piece {
        let x: Double, speed: Double, phase: Double, sway: Double, spin: Double
        let w: CGFloat, h: CGFloat
        let color: Color
        init(using rng: inout SeededGen, palette: [Color]) {
            x = .random(in: 0...1, using: &rng)
            speed = .random(in: 0.05...0.13, using: &rng)
            phase = .random(in: 0...1, using: &rng)
            sway = .random(in: 0.6...1.7, using: &rng)
            spin = .random(in: -2.4...2.4, using: &rng)
            w = .random(in: 10...18, using: &rng)
            h = .random(in: 14...26, using: &rng)
            color = palette.randomElement(using: &rng) ?? .yellow
        }
    }
}

/// Tiny deterministic RNG (SplitMix64) so confetti looks the same each run and
/// needs no per-frame allocation.
private struct SeededGen: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Stars

private struct StarsRow: View {
    let count: Int
    let shown: Bool

    var body: some View {
        HStack(spacing: 22) {
            ForEach(0..<count, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: 78, weight: .black))
                    .foregroundStyle(
                        LinearGradient(colors: RewardPalette.gold, startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: RewardPalette.gold[1].opacity(0.8), radius: 14, y: 4)
                    .scaleEffect(shown ? 1 : 0.01)
                    .rotationEffect(.degrees(shown ? 0 : -50))
                    .animation(.spring(response: 0.5, dampingFraction: 0.45)
                        .delay(0.55 + Double(i) * 0.18), value: shown)
            }
        }
    }
}

// MARK: - Sticker reveal

private struct StickerReveal: View {
    let stickerId: String?
    let title: String
    let name: String
    let animate: Bool
    let shown: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(RewardPalette.deepBlue)
                .textCase(.uppercase)
                .tracking(2)

            ZStack {
                // Glow halo
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(RewardPalette.gold[0])
                    .blur(radius: 26)
                    .opacity(shown ? 0.7 : 0)

                // The sticker tile
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: StickerArt.colors(for: stickerId),
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Image(systemName: StickerArt.symbol(for: stickerId))
                            .font(.system(size: 96, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 5)
                    )
                    .overlay(ShineSweep(active: animate && shown)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)))
                    .frame(width: 220, height: 220)
            }
            .scaleEffect(shown ? 1 : 0.55)
            .rotation3DEffect(.degrees(shown ? 0 : 95), axis: (x: 0, y: 1, z: 0))
            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(animate ? 1.15 : 0.15), value: shown)

            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(animate ? 1.5 : 0.2), value: shown)
            }
        }
    }
}

/// A diagonal gloss that sweeps across the sticker, like an item unlock.
private struct ShineSweep: View {
    let active: Bool
    @State private var x: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.65), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: geo.size.width * 0.6)
                .rotationEffect(.degrees(18))
                .offset(x: x * geo.size.width * 1.6)
                .onChange(of: active) { _, on in if on { start() } }
                .onAppear { if active { start() } }
        }
    }

    private func start() {
        x = -1
        withAnimation(.easeInOut(duration: 1.4).delay(1.4).repeatForever(autoreverses: false)) {
            x = 1
        }
    }
}

// MARK: - Continue button

private struct ContinueButton: View {
    let title: String
    let animate: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "house.fill")
                Text(title)
            }
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .frame(minWidth: 460, minHeight: 88)
        }
        .buttonStyle(.borderedProminent)
        .tint(RewardPalette.deepBlue)
        .scaleEffect(pulse ? 1.04 : 1.0)
        .animation(animate ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil, value: pulse)
        .onAppear { pulse = true }
    }
}

// MARK: - Sticker art catalog (id → drawn placeholder)

/// Maps a sticker id to a drawn placeholder (SF Symbol + cozy gradient). Real
/// sticker artwork can replace these later behind the same ids (D-ART-1).
enum StickerArt {
    static func symbol(for id: String?) -> String {
        switch id {
        case "first-day": return "bus.fill"
        default:          return "star.fill"
        }
    }

    static func colors(for id: String?) -> [Color] {
        switch id {
        case "first-day":
            return [Color(red: 1.0, green: 0.82, blue: 0.30), Color(red: 1.0, green: 0.58, blue: 0.24)]
        default:
            return [Color(red: 0.40, green: 0.76, blue: 1.0), Color(red: 0.16, green: 0.45, blue: 0.86)]
        }
    }
}
