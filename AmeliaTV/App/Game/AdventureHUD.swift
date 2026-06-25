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

/// A building's flat top-down footprint in world coordinates — centre plus its
/// half-width (along x) and half-depth (along z). The map draws these as
/// rectangles over the roads so you can *see* where a building sits relative to
/// the streets (e.g. when one is accidentally placed in a road).
struct MapFootprint: Equatable {
    var x: Double
    var z: Double
    var hw: Double
    var hd: Double
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
    /// Every building footprint in the town, in world coordinates. Published once
    /// by the scene after the world is built; drawn on the minimap / full map.
    @Published var buildings: [MapFootprint] = []
}

/// The on-screen HUD: an objective pill (top-left), a star counter + minimap
/// (top-right), and a character subtitle bar (bottom). Drawn over the SpriteKit
/// scene. Everything except the minimap is non-interactive so it never steals
/// focus or touches; the minimap is tappable (on iOS) to open a full-screen,
/// pinch-to-zoom map of the whole town.
///
/// Sizes scale with the rendered 16:9 canvas: the design target is the 1920×1080
/// Apple TV screen, so on a small iPhone everything shrinks proportionally
/// instead of rendering at TV-sized points (which looked massive on phone).
struct AdventureHUDView: View {
    @ObservedObject var hud: AdventureHUD
    @State private var showFullMap = false

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
                            .allowsHitTesting(false)
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
                        .allowsHitTesting(false)

                        // The minimap is tappable on iOS — open the full-screen map.
                        MinimapView(state: hud.minimap, buildings: hud.buildings, scale: s)
                            #if os(iOS)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 13 * s, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(5 * s)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                    .padding(6 * s)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showFullMap = true }
                            #endif
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
                    .allowsHitTesting(false)
                }
            }
            .padding(40 * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.25), value: hud.objective)
        .animation(.easeInOut(duration: 0.25), value: hud.subtitle)
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullMap) {
            FullMapView(state: hud.minimap, buildings: hud.buildings) { showFullMap = false }
        }
        #endif
    }
}

/// Draw the whole town map — grass, roads (at their real drivable width so you
/// can see what overlaps them), building footprints, the goal pin, and the bus
/// arrow — into a `Canvas` of the given pixel `size`. Roads and buildings share
/// one world→screen scale, so a building drawn over a road on screen is genuinely
/// sitting in that road in the world. `lod` scales line widths / marker sizes.
///
/// North is up: world +x → right, world +z → down (south).
func drawTownMap(_ ctx: GraphicsContext, size: CGSize,
                 net: RoadNetwork, buildings: [MapFootprint],
                 state: MinimapState, lod: CGFloat, showBus: Bool) {
    // Whole-canvas grass, so the map reads as a map even before the rounded clip.
    ctx.fill(Path(CGRect(origin: .zero, size: size)),
             with: .color(Color(red: 0.46, green: 0.73, blue: 0.42)))

    // World bounds over both roads AND buildings (buildings sit outside the road
    // box on the frontages, so they must count toward the extent).
    var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
    var minZ = Double.greatestFiniteMagnitude, maxZ = -Double.greatestFiniteMagnitude
    for seg in net.segments {
        minX = min(minX, seg.a.x, seg.b.x); maxX = max(maxX, seg.a.x, seg.b.x)
        minZ = min(minZ, seg.a.z, seg.b.z); maxZ = max(maxZ, seg.a.z, seg.b.z)
    }
    for b in buildings {
        minX = min(minX, b.x - b.hw); maxX = max(maxX, b.x + b.hw)
        minZ = min(minZ, b.z - b.hd); maxZ = max(maxZ, b.z + b.hd)
    }
    let pad = 60.0
    minX -= pad; maxX += pad; minZ -= pad; maxZ += pad
    let span = max(1, max(maxX - minX, maxZ - minZ))   // square / undistorted
    let inset = 8 * lod
    let usable = min(size.width, size.height) - inset * 2
    // centre the (square) world span inside the (possibly non-square) canvas
    let ox = inset + (size.width - inset * 2 - usable) / 2
    let oy = inset + (size.height - inset * 2 - usable) / 2
    let k = usable / CGFloat(span)                     // world units → points
    func mp(_ x: Double, _ z: Double) -> CGPoint {
        CGPoint(x: ox + CGFloat(x - minX) * k, y: oy + CGFloat(z - minZ) * k)
    }

    // Roads at real drivable width (light asphalt) so overlaps read true-to-life.
    let roadColor = Color(red: 0.40, green: 0.41, blue: 0.45)
    for seg in net.segments {
        var p = Path()
        p.move(to: mp(seg.a.x, seg.a.z)); p.addLine(to: mp(seg.b.x, seg.b.z))
        ctx.stroke(p, with: .color(roadColor),
                   style: StrokeStyle(lineWidth: max(1, CGFloat(seg.width) * k),
                                      lineCap: .round, lineJoin: .round))
    }

    // Building footprints — warm rectangles with a crisp outline, drawn over the
    // roads (exactly as in the world), so a building in a street is obvious.
    let wall = Color(red: 0.80, green: 0.62, blue: 0.50)
    let wallEdge = Color(red: 0.32, green: 0.22, blue: 0.16)
    for b in buildings {
        let c = mp(b.x, b.z)
        let rect = CGRect(x: c.x - CGFloat(b.hw) * k, y: c.y - CGFloat(b.hd) * k,
                          width: CGFloat(b.hw) * 2 * k, height: CGFloat(b.hd) * 2 * k)
        let path = Path(roundedRect: rect, cornerRadius: 1.5 * lod)
        ctx.fill(path, with: .color(wall))
        ctx.stroke(path, with: .color(wallEdge), lineWidth: max(0.6, 1 * lod))
    }

    // Goal pin.
    if let gx = state.goalX, let gz = state.goalZ {
        let g = mp(gx, gz)
        let r: CGFloat = 5 * lod
        let rect = CGRect(x: g.x - r, y: g.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 1, green: 0.82, blue: 0.25)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5 * lod)
    }

    // Bus arrow (heading 0 = +x = east; screen shares world's x-right/y-down).
    if showBus {
        let bp = mp(state.busX, state.busZ)
        let h = CGFloat(state.heading)
        let r: CGFloat = 7 * lod
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
        ctx.stroke(tri, with: .color(.white), lineWidth: 1.5 * lod)
    }
}

/// A north-up locator map of the whole town: roads, building footprints, the goal
/// pin, and a bus arrow showing where you are and which way you're pointing. Reads
/// the static road network directly; the bus/goal/buildings come from the HUD.
struct MinimapView: View {
    let state: MinimapState
    let buildings: [MapFootprint]
    let scale: CGFloat

    private let net = RoadNetwork.welles

    var body: some View {
        let dim = 150 * scale
        Canvas { ctx, size in
            drawTownMap(ctx, size: size, net: net, buildings: buildings,
                        state: state, lod: scale, showBus: true)
        }
        .frame(width: dim, height: dim)
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale)
                .strokeBorder(.white.opacity(0.8), lineWidth: 2 * scale)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        .shadow(color: .black.opacity(0.25), radius: 4 * scale, y: 2 * scale)
    }
}

#if os(iOS)
/// A full-screen map of the whole town you can pinch-to-zoom and drag to pan
/// (double-tap resets). Opened by tapping the minimap. Shows roads at real width
/// with every building footprint, so it doubles as a layout view for spotting a
/// building that's sitting in a street.
struct FullMapView: View {
    let state: MinimapState
    let buildings: [MapFootprint]
    let onClose: () -> Void

    private let net = RoadNetwork.welles

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.12, blue: 0.14).ignoresSafeArea()

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                Canvas { ctx, size in
                    drawTownMap(ctx, size: size, net: net, buildings: buildings,
                                state: state, lod: 2.2, showBus: true)
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25), lineWidth: 2))
                .scaleEffect(max(1, zoom * pinch))
                .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, st, _ in st = value }
                        .onEnded { value in zoom = min(8, max(1, zoom * value)) }
                        .simultaneously(with:
                            DragGesture()
                                .updating($drag) { value, st, _ in st = value.translation }
                                .onEnded { value in
                                    offset.width += value.translation.width
                                    offset.height += value.translation.height
                                }
                        )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) { zoom = 1; offset = .zero }
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text("Map")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                }
                Spacer()
                Text("Pinch to zoom • Drag to pan • Double-tap to reset")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .padding(24)
        }
    }
}
#endif

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
