import SwiftUI
import AmeliaCore

/// Where the bus is, where it's headed, and where its goal is — in world
/// coordinates — for the on-screen minimap. Bundled into one value so the scene
/// publishes a single change per frame instead of one per property.
struct MinimapState: Equatable {
    var busX: Double = 0
    var busZ: Double = 0
    var heading: Double = 0       // radians, 0 = +x (east)
    var goalX: Double? = nil
    var goalZ: Double? = nil
}

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
    /// Bus location + goal for the minimap.
    @Published var minimap = MinimapState()
}

/// The on-screen HUD: an objective pill (top-left), a star counter + minimap
/// (top-right), and a character subtitle bar (bottom). Drawn over the SpriteKit
/// scene and non-interactive so it never steals focus or touches.
///
/// Sizes scale with the rendered 16:9 canvas: the design target is the 1920×1080
/// Apple TV screen, so on a small iPhone everything shrinks proportionally
/// instead of rendering at TV-sized points (which looked massive on phone).
struct AdventureHUDView: View {
    @ObservedObject var hud: AdventureHUD

    var body: some View {
        GeometryReader { geo in
            // 1.0 on a 1920×1080 TV; smaller on iPhone/iPad. Floored so it never
            // gets unreadably tiny, capped at 1.0 so it never grows past the design.
            let s = min(1.0, max(0.42, min(geo.size.width / 1920, geo.size.height / 1080)))

            VStack {
                HStack(alignment: .top) {
                    if !hud.objective.isEmpty {
                        Label(hud.objective, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 30 * s, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22 * s).padding(.vertical, 12 * s)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 2 * s))
                            .transition(.opacity)
                            .id(hud.objective)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12 * s) {
                        HStack(spacing: 8 * s) {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                                .font(.system(size: 28 * s))
                            Text("\(hud.stars)")
                                .font(.system(size: 32 * s, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 22 * s).padding(.vertical, 10 * s)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 2 * s))

                        MinimapView(state: hud.minimap, scale: s)
                    }
                }

                Spacer()

                if !hud.subtitle.isEmpty {
                    VStack(spacing: 4 * s) {
                        if !hud.speakerName.isEmpty {
                            Text(hud.speakerName)
                                .font(.system(size: 22 * s, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: hud.speakerColorHex) ?? .teal)
                        }
                        Text(hud.subtitle)
                            .font(.system(size: 30 * s, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28 * s).padding(.vertical, 16 * s)
                    .background(RoundedRectangle(cornerRadius: 20 * s).fill(Color.black.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 20 * s).strokeBorder(.white.opacity(0.6), lineWidth: 2 * s))
                    .padding(.bottom, 8 * s)
                    .transition(.opacity)
                    .id(hud.subtitle)
                }
            }
            .padding(40 * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.25), value: hud.objective)
        .animation(.easeInOut(duration: 0.25), value: hud.subtitle)
        .allowsHitTesting(false)
    }
}

/// A north-up locator map of the whole town: roads, the goal pin, and a bus
/// arrow showing where you are and which way you're pointing. Reads the static
/// road network directly; the bus/goal come live from `MinimapState`.
struct MinimapView: View {
    let state: MinimapState
    let scale: CGFloat

    private let net = RoadNetwork.welles

    var body: some View {
        let dim = 150 * scale
        Canvas { ctx, size in
            // World bounds (with a little margin) → minimap rect.
            var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
            var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
            for seg in net.segments {
                minX = min(minX, seg.a.x, seg.b.x); maxX = max(maxX, seg.a.x, seg.b.x)
                minZ = min(minZ, seg.a.z, seg.b.z); maxZ = max(maxZ, seg.a.z, seg.b.z)
            }
            let pad = 80.0
            minX -= pad; maxX += pad; minZ -= pad; maxZ += pad
            let spanX = max(1, maxX - minX), spanZ = max(1, maxZ - minZ)
            let span = max(spanX, spanZ)               // keep it square / undistorted
            let inset: CGFloat = 8 * scale
            let usable = min(size.width, size.height) - inset * 2
            // world → minimap point (north up: +z is south = downward, matching y)
            func mp(_ x: Double, _ z: Double) -> CGPoint {
                CGPoint(x: inset + CGFloat((x - minX) / span) * usable,
                        y: inset + CGFloat((z - minZ) / span) * usable)
            }

            // roads
            let roadColor = Color(red: 0.32, green: 0.34, blue: 0.38)
            for seg in net.segments {
                var p = Path()
                p.move(to: mp(seg.a.x, seg.a.z)); p.addLine(to: mp(seg.b.x, seg.b.z))
                ctx.stroke(p, with: .color(roadColor),
                           style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, lineJoin: .round))
            }

            // goal pin
            if let gx = state.goalX, let gz = state.goalZ {
                let g = mp(gx, gz)
                let r: CGFloat = 5 * scale
                let rect = CGRect(x: g.x - r, y: g.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 1, green: 0.82, blue: 0.25)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5 * scale)
            }

            // bus arrow (heading 0 = +x = east; screen shares world's x-right/y-down)
            let bp = mp(state.busX, state.busZ)
            let h = CGFloat(state.heading)
            let r: CGFloat = 7 * scale
            func rot(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
                CGPoint(x: bp.x + dx * cos(h) - dy * sin(h),
                        y: bp.y + dx * sin(h) + dy * cos(h))
            }
            var tri = Path()
            tri.move(to: rot(r, 0))
            tri.addLine(to: rot(-r * 0.75, -r * 0.7))
            tri.addLine(to: rot(-r * 0.75, r * 0.7))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(red: 0.23, green: 0.63, blue: 1)))
            ctx.stroke(tri, with: .color(.white), lineWidth: 1.5 * scale)
        }
        .frame(width: dim, height: dim)
        .background(
            RoundedRectangle(cornerRadius: 14 * scale)
                .fill(Color(red: 0.46, green: 0.73, blue: 0.42).opacity(0.9))   // grass, matches the scene
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale)
                .strokeBorder(.white.opacity(0.8), lineWidth: 2 * scale)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        .shadow(color: .black.opacity(0.25), radius: 4 * scale, y: 2 * scale)
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
