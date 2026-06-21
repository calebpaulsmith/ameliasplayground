import SwiftUI
import AmeliaCore

/// A single, value-type snapshot of everything the HUD draws. The render engine
/// rebuilds this from `GameSession` each frame and publishes it; the HUD is a
/// thin, stateless reflection of core state (docs/tvos/GAME_DESIGN.md §5, A2-10).
struct HUDModel: Equatable {
    var stars: Int = 0
    var collected: Int = 0
    var subtitle: String = ""
    var turnCue: TurnCue = .straight
    var drivePrompt: GameSession.DrivePrompt = .go
    var destinationNameId: String? = nil
    var awaitingChoice: Bool = false
    // "Spot it" (find) question is active: the answer balloons float in the 3D world
    // and the child steers + beeps to pick one, so the HUD only shows a gentle hint.
    var awaitingFind: Bool = false
    var finished: Bool = false

    // Reward screen (A2-12): what the finished episode awarded.
    var rewardStars: Int = 0
    var rewardStickerId: String? = nil

    // Minimap (world units; the map computes its own bounds from the places).
    var busX: Double = 0
    var busZ: Double = 0
    var busHeading: Double = 0
    var targetX: Double? = nil
    var targetZ: Double? = nil
    var places: [HUDPlace] = []
}

struct HUDPlace: Equatable, Identifiable {
    let id: String
    let x: Double
    let z: Double
    let colorHex: String?
    let isTarget: Bool
}

/// Big, couch-readable guidance overlaid on the 3D scene: a star counter, a
/// GO/STOP badge, a pulsing turn arrow toward the destination, the spoken
/// subtitle, and a small minimap. Minimal text, large targets, bilingual.
struct HUDView: View {
    @EnvironmentObject private var session: AppSession
    let model: HUDModel
    /// On-screen turn buttons call these (used for the fork choice, esp. on touch
    /// devices with no controller). No-ops by default.
    var onTurnLeft: () -> Void = {}
    var onTurnRight: () -> Void = {}
    /// Tapped on the reward screen's "back to the garage" button.
    var onContinue: () -> Void = {}

    var body: some View {
        ZStack {
            if model.finished {
                // The episode is over: the reward screen takes over the whole HUD.
                RewardView(stars: model.rewardStars,
                           stickerId: model.rewardStickerId,
                           onContinue: onContinue)
                    .environmentObject(session)
            } else {
                drivingHUD
                    .adaptiveTVCanvas()
            }
        }
    }

    /// The live driving overlay (stars, GO/STOP, turn arrow, minimap, subtitle).
    private var drivingHUD: some View {
        ZStack {
            // Top row: stars (left) and destination (right).
            VStack {
                HStack(alignment: .top) {
                    StarCounter(count: model.stars)
                    if model.collected > 0 { CollectibleCounter(count: model.collected) }
                    Spacer()
                    if let nameId = model.destinationNameId {
                        DestinationBadge(name: session.string(nameId))
                    }
                }
                Spacer()
            }

            // Center guidance: the big GO/STOP badge with the turn arrow.
            VStack(spacing: 28) {
                Spacer()
                TurnArrow(cue: model.turnCue)
                DrivePromptBadge(prompt: model.drivePrompt,
                                 go: session.string("ui.go"),
                                 stop: session.string("ui.stop"))
                if model.awaitingChoice {
                    ChoiceButtons(onLeft: onTurnLeft, onRight: onTurnRight)
                }
                if model.awaitingFind {
                    FindHint()
                }
                Spacer()
            }

            // Bottom: minimap (left) and a brief, self-dismissing subtitle (center).
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 24) {
                    Minimap(model: model)
                        .frame(width: 240, height: 180)
                    SubtitleBar(text: model.subtitle)
                    Spacer()
                }
            }
        }
        .padding(56)
    }
}

// MARK: - Pieces

/// Big left/right buttons shown at the fork. Tappable on touch devices and
/// focusable with a remote/controller — the one interactive choice in the slice.
private struct ChoiceButtons: View {
    let onLeft: () -> Void
    let onRight: () -> Void

    var body: some View {
        HStack(spacing: 64) {
            button(system: "arrow.left.circle.fill", action: onLeft)
            button(system: "arrow.right.circle.fill", action: onRight)
        }
        .padding(.top, 12)
    }

    private func button(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 96, weight: .black))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color(red: 0.12, green: 0.43, blue: 0.81)))
                .shadow(radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// A wordless cue during a "spot it" question: the answer balloons live in the 3D
/// world (steer to aim, beep to pick), so the HUD shows only a pulsing horn so a
/// young child knows to beep — no sentence to read.
private struct FindHint: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "horn.fill")
            .font(.system(size: 48, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 108, height: 108)
            .background(Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.20)))
            .shadow(radius: 10, y: 6)
            .scaleEffect(pulse ? 1.08 : 0.94)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .padding(.top, 12)
    }
}

/// The spoken line, mirrored as a small caption that **fades itself out** a few
/// seconds after it changes — so guidance is a brief glance, not a wall of text
/// parked on screen. Smaller and lighter than before; the gameplay leads.
private struct SubtitleBar: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Group {
            if shown && !text.isEmpty {
                Text(text)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .transition(.opacity)
            }
        }
        // Re-runs whenever the line changes: show it, then quietly hide after 4s.
        .task(id: text) {
            guard !text.isEmpty else { return }
            withAnimation(.easeIn(duration: 0.2)) { shown = true }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeOut(duration: 0.6)) { shown = false }
        }
    }
}

private struct StarCounter: View {
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill").foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25))
            Text("\(count)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: count)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// A little tally of balloons/coins scooped on the route — appears only once the
/// child has grabbed their first one.
private struct CollectibleCounter: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "balloon.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.37, blue: 0.48))
            Text("\(count)")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: count)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct DestinationBadge: View {
    let name: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(Color(red: 0.18, green: 0.78, blue: 0.72))
            Text(name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct DrivePromptBadge: View {
    let prompt: GameSession.DrivePrompt
    let go: String
    let stop: String

    private var isStop: Bool { prompt == .stop }

    var body: some View {
        Text(isStop ? stop : go)
            .font(.system(size: 72, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 64).padding(.vertical, 22)
            .background(
                Capsule().fill(isStop
                    ? Color(red: 0.90, green: 0.21, blue: 0.21)
                    : Color(red: 0.20, green: 0.72, blue: 0.36))
            )
            .shadow(radius: 12, y: 6)
            .animation(.snappy, value: isStop)
    }
}

/// A large arrow that points the way and gently pulses to draw a young child's
/// eye. Hidden when simply driving straight so it never distracts.
private struct TurnArrow: View {
    let cue: TurnCue
    @State private var pulse = false

    private var symbol: String? {
        switch cue {
        case .straight: return nil
        case .left:     return "arrow.turn.up.left"
        case .right:    return "arrow.turn.up.right"
        case .uTurn:    return "arrow.uturn.down"
        case .arrive:   return "flag.checkered.circle.fill"
        }
    }

    var body: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 120, weight: .black))
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25))
                .shadow(radius: 10, y: 6)
                .scaleEffect(pulse ? 1.12 : 0.92)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// A top-down minimap: place dots, the active destination ringed, and the bus as
/// a heading triangle. Bounds are derived from the place set with a margin.
private struct Minimap: View {
    let model: HUDModel

    var body: some View {
        GeometryReader { geo in
            let bounds = mapBounds()
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.42, green: 0.74, blue: 0.40).opacity(0.85))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.6), lineWidth: 3)

                ForEach(model.places) { place in
                    let p = project(x: place.x, z: place.z, in: geo.size, bounds: bounds)
                    Circle()
                        .fill(Color(hex: place.colorHex) ?? .white)
                        .frame(width: place.isTarget ? 22 : 14, height: place.isTarget ? 22 : 14)
                        .overlay {
                            if place.isTarget {
                                Circle().strokeBorder(.white, lineWidth: 3)
                            }
                        }
                        .position(p)
                }

                let bus = project(x: model.busX, z: model.busZ, in: geo.size, bounds: bounds)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.13, green: 0.45, blue: 0.95))
                    .rotationEffect(.radians(model.busHeading))
                    .position(bus)
            }
        }
    }

    private struct Bounds { var minX, maxX, minZ, maxZ: Double }

    private func mapBounds() -> Bounds {
        var b = Bounds(minX: model.busX, maxX: model.busX, minZ: model.busZ, maxZ: model.busZ)
        for p in model.places {
            b.minX = min(b.minX, p.x); b.maxX = max(b.maxX, p.x)
            b.minZ = min(b.minZ, p.z); b.maxZ = max(b.maxZ, p.z)
        }
        // Pad so dots never touch the edge.
        let padX = max((b.maxX - b.minX) * 0.12, 8)
        let padZ = max((b.maxZ - b.minZ) * 0.12, 8)
        b.minX -= padX; b.maxX += padX; b.minZ -= padZ; b.maxZ += padZ
        return b
    }

    private func project(x: Double, z: Double, in size: CGSize, bounds: Bounds) -> CGPoint {
        let w = max(bounds.maxX - bounds.minX, 0.001)
        let h = max(bounds.maxZ - bounds.minZ, 0.001)
        let inset: CGFloat = 16
        let px = inset + CGFloat((x - bounds.minX) / w) * (size.width - 2 * inset)
        let py = inset + CGFloat((z - bounds.minZ) / h) * (size.height - 2 * inset)
        return CGPoint(x: px, y: py)
    }
}

// MARK: - Color helper

private extension Color {
    /// Parses `#rrggbb` (case-insensitive). Returns nil for unparseable input.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xff) / 255.0,
            green: Double((v >> 8) & 0xff) / 255.0,
            blue: Double(v & 0xff) / 255.0
        )
    }
}
