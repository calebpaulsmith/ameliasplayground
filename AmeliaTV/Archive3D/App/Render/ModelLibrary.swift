import Foundation

#if canImport(RealityKit)
import RealityKit

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// Addressable face parts of a character so the engine can give it life: blink
/// (squash the eyes), and look (offset the pupils from their neutral position).
/// Built once with the entity and animated each frame (GAME_DESIGN.md §4a).
struct FaceRig {
    let eyes: [ModelEntity]            // the white sclera spheres
    let pupils: [ModelEntity]          // the dark pupils
    let pupilRest: [SIMD3<Float>]      // each pupil's neutral local position
}

/// Resolves a model **id** to a RealityKit `Entity`, loading a USDZ from the app
/// bundle when present and otherwise returning a primitive placeholder. This is
/// the swap-without-code-changes guarantee from docs/tvos/ (F1-06): gameplay
/// never waits on final art, and art can be upgraded later by dropping in a
/// USDZ named after the id.
enum ModelLibrary {

    /// Loads `\(name).usdz` from the app bundle, or nil if absent/unloadable. The
    /// one place we resolve real art so every model id swaps in the same way.
    static func loadUSDZ(_ name: String) -> Entity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let loaded = try? Entity.load(contentsOf: url) else { return nil }
        return loaded
    }

    /// Loads `\(id).usdz` from the bundle, or builds a colored placeholder box.
    static func entity(id: String, placeholderColor: PlatformColor, size: SIMD3<Float>) -> Entity {
        loadUSDZ(id) ?? placeholderBox(color: placeholderColor, size: size)
    }

    static func placeholderBox(color: PlatformColor, size: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: size, cornerRadius: size.y * 0.18)
        let material = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// The bus, with two big friendly eyes on its forward (+x) face — the cozy
    /// "friendly vehicle" genre look in original geometry (D-IP-1). Resolves a
    /// `bus.usdz` if present, else a coloured placeholder box.
    static func busEntity(placeholderColor: PlatformColor) -> Entity {
        busRig(placeholderColor: placeholderColor).root
    }

    /// Like `busEntity`, but also returns a `FaceRig` so the engine can blink and
    /// look around (Character Life pass — docs/tvos/GAME_DESIGN.md §4a). The eyes
    /// are kept addressable instead of anonymous children.
    ///
    /// Real art wins outright: if `bus.usdz` is in the bundle it's returned as-is
    /// (it carries its own face), and the rig is empty (the engine's face animation
    /// safely no-ops). Otherwise we build a cute, recognisable placeholder bus.
    static func busRig(placeholderColor: PlatformColor) -> (root: Entity, face: FaceRig) {
        if let loaded = loadUSDZ("bus") {
            return (loaded, FaceRig(eyes: [], pupils: [], pupilRest: []))
        }
        return builtBus(color: placeholderColor)
    }

    /// A friendly little bus from primitives: a rounded body, a white roof, blue
    /// side windows, four chunky wheels, a bumper — and the big animated face on
    /// its forward (+x) windshield. Sized to match the old placeholder box (≈1.6 ×
    /// 1.1 × 0.9) so face/headlight offsets and the ground line are unchanged.
    private static func builtBus(color: PlatformColor) -> (root: Entity, face: FaceRig) {
        let root = Entity()

        // Body.
        let body = placeholderBox(color: color, size: [1.6, 1.0, 0.9])
        body.position = [0, 0.05, 0]
        root.addChild(body)

        // White roof cap, set back a touch so the face/windshield reads at the front.
        let roof = placeholderBox(color: PlatformColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1),
                                  size: [1.4, 0.2, 0.82])
        roof.position = [-0.06, 0.6, 0]
        root.addChild(roof)

        // Blue side windows.
        let glass = PlatformColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1)
        for z in [Float(-0.46), 0.46] {
            let win = placeholderBox(color: glass, size: [1.0, 0.34, 0.05])
            win.position = [-0.12, 0.28, z]
            root.addChild(win)
        }

        // Four chunky wheels (axle along z), resting on the same ground line as the
        // old box (lowest point at y = -0.55).
        let tyre = PlatformColor(white: 0.14, alpha: 1)
        let hubColor = PlatformColor(white: 0.78, alpha: 1)
        for x in [Float(-0.52), 0.52] {
            for z in [Float(-0.47), 0.47] {
                let w = sphere(radius: 0.2, color: tyre)
                w.scale = [1, 1, 0.55]                     // flatten into a disc
                w.position = [x, -0.35, z]
                root.addChild(w)
                let hub = sphere(radius: 0.07, color: hubColor)
                hub.position = [x, -0.35, z + (z > 0 ? 0.12 : -0.12)]
                root.addChild(hub)
            }
        }

        // A pale front bumper.
        let bumper = placeholderBox(color: PlatformColor(white: 0.88, alpha: 1), size: [0.14, 0.16, 0.78])
        bumper.position = [0.78, -0.36, 0]
        root.addChild(bumper)

        // The face on the +x windshield: big eyes (white + pupil + catch-light),
        // rosy cheeks and a happy grin — kept addressable for blink/look.
        var eyes: [ModelEntity] = []
        var pupils: [ModelEntity] = []
        var rest: [SIMD3<Float>] = []
        for z in [Float(-0.24), 0.24] {
            let white = sphere(radius: 0.17, color: .white)
            white.position = [0.78, 0.18, z]
            white.name = "eye"
            root.addChild(white)
            eyes.append(white)
            let pupil = sphere(radius: 0.075, color: PlatformColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1))
            let p: SIMD3<Float> = [0.9, 0.18, z]
            pupil.position = p
            pupil.name = "pupil"
            root.addChild(pupil)
            pupils.append(pupil)
            rest.append(p)
            addEyeHighlight(to: root, near: p, radius: 0.03)
        }
        addCheeks(to: root, atX: 0.81, y: -0.02, spacing: 0.40, radius: 0.12)
        addSmile(to: root, atX: 0.83, y: -0.20, width: 0.46, beadRadius: 0.05, lift: 0.13)
        return (root, FaceRig(eyes: eyes, pupils: pupils, pupilRest: rest))
    }

    static func ground(size: Float, color: PlatformColor) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: size, depth: size)
        let material = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    static func sphere(radius: Float, color: PlatformColor) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// A glossy white catch-light on a pupil — the little dot that makes eyes read
    /// as alive rather than as flat black beads. Placed up-and-out on the +x face.
    private static func addEyeHighlight(to node: Entity, near pupil: SIMD3<Float>, radius: Float) {
        let hi = sphere(radius: radius, color: .white)
        hi.position = [pupil.x + radius * 0.6, pupil.y + radius * 0.9, pupil.z - radius * 0.9]
        node.addChild(hi)
    }

    /// Two soft, rosy cheeks on the +x face — instant "cute". Flattened against the
    /// face so they read as a blush, not as bumps.
    private static func addCheeks(to node: Entity, atX x: Float, y: Float, spacing: Float, radius: Float) {
        for z in [-spacing, spacing] {
            let cheek = sphere(radius: radius,
                               color: PlatformColor(red: 1.0, green: 0.60, blue: 0.66, alpha: 0.92))
            cheek.scale = [0.28, 0.8, 1]
            cheek.position = [x, y, z]
            node.addChild(cheek)
        }
    }

    /// A cheerful upturned smile on the +x face: a row of little dark beads in a
    /// shallow arc that lifts at the corners. Purely cosmetic (no FaceRig handle).
    private static func addSmile(to node: Entity, atX x: Float, y: Float,
                                 width: Float, beadRadius: Float, lift: Float) {
        let count = 5
        let dark = PlatformColor(red: 0.30, green: 0.16, blue: 0.18, alpha: 1)
        for i in 0..<count {
            let t = Float(i) / Float(count - 1)        // 0…1 left → right
            let u = (t - 0.5) * 2                        // -1…1
            let bead = sphere(radius: beadRadius, color: dark)
            bead.scale = [0.45, 1, 1]                    // flatten against the face
            bead.position = [x, y + u * u * lift, (t - 0.5) * width]
            node.addChild(bead)
        }
    }

    /// A friendly Rescue-Team vehicle, built from primitives with two big eyes on
    /// its forward (+x) windshield. Distinct silhouette per `role`. Loads
    /// `\(modelRef).usdz` if present, else builds an original placeholder.
    /// All-original designs (D-IP-1).
    static func vehicle(modelRef: String, role: String, color: PlatformColor) -> Entity {
        if let loaded = loadUSDZ(modelRef) { return loaded }
        return role == "helicopter" ? builtHelicopter(color: color)
                                    : builtGroundVehicle(role: role, color: color)
    }

    /// A whole friendly face on the +x face: two eyes (white + pupil + catch-light),
    /// rosy cheeks, and a happy grin — so every rescue friend looks cute, not boxy.
    private static func addEyes(to node: Entity, atX x: Float, y: Float,
                               spacing: Float = 0.18, scale: Float = 1) {
        for z in [-spacing, spacing] {
            let white = sphere(radius: 0.13 * scale, color: .white)
            white.position = [x, y, z]
            node.addChild(white)
            let p: SIMD3<Float> = [x + 0.1 * scale, y, z]
            let pupil = sphere(radius: 0.055 * scale,
                               color: PlatformColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1))
            pupil.position = p
            node.addChild(pupil)
            addEyeHighlight(to: node, near: p, radius: 0.022 * scale)
        }
        addCheeks(to: node, atX: x, y: y - 0.17 * scale,
                  spacing: spacing + 0.07 * scale, radius: 0.085 * scale)
        addSmile(to: node, atX: x + 0.02 * scale, y: y - 0.30 * scale,
                 width: spacing * 2.2, beadRadius: 0.04 * scale, lift: 0.10 * scale)
    }

    private static func wheel() -> ModelEntity {
        let w = sphere(radius: 0.22, color: PlatformColor(white: 0.16, alpha: 1))
        w.scale = [1, 1, 0.5]          // flatten into a disc (axle along z)
        return w
    }

    private static func builtGroundVehicle(role: String, color: PlatformColor) -> Entity {
        let node = Entity()
        let body = placeholderBox(color: color, size: [1.5, 0.7, 0.9])
        body.position = [0, 0.5, 0]
        node.addChild(body)
        let cabin = placeholderBox(color: color, size: [0.7, 0.55, 0.84])
        cabin.position = [0.42, 1.0, 0]
        node.addChild(cabin)
        for x in [Float(-0.5), 0.5] {
            for z in [Float(-0.46), 0.46] {
                let w = wheel()
                w.position = [x, 0.22, z]
                node.addChild(w)
            }
        }
        addEyes(to: node, atX: 0.78, y: 1.02)

        switch role {
        case "fire":
            let ladder = placeholderBox(color: PlatformColor(white: 0.85, alpha: 1),
                                        size: [1.3, 0.08, 0.12])
            ladder.position = [-0.15, 1.05, 0]
            ladder.orientation = simd_quatf(angle: -0.18, axis: [0, 0, 1])
            node.addChild(ladder)
        case "tow":
            let arm = placeholderBox(color: PlatformColor(white: 0.30, alpha: 1),
                                     size: [0.8, 0.1, 0.12])
            arm.position = [-0.7, 1.0, 0]
            arm.orientation = simd_quatf(angle: 0.5, axis: [0, 0, 1])
            node.addChild(arm)
            let hook = placeholderBox(color: PlatformColor(white: 0.22, alpha: 1),
                                      size: [0.12, 0.18, 0.12])
            hook.position = [-1.05, 1.18, 0]
            node.addChild(hook)
        case "ambulance":
            let bar = placeholderBox(color: PlatformColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1),
                                     size: [0.42, 0.12, 0.5])
            bar.position = [0.1, 1.34, 0]
            node.addChild(bar)
            let crossV = placeholderBox(color: PlatformColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),
                                        size: [0.06, 0.34, 0.05])
            crossV.position = [-0.2, 0.55, 0.46]
            node.addChild(crossV)
            let crossH = placeholderBox(color: PlatformColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),
                                        size: [0.34, 0.06, 0.05])
            crossH.position = [-0.2, 0.55, 0.46]
            node.addChild(crossH)
        default:
            break
        }
        return node
    }

    private static func builtHelicopter(color: PlatformColor) -> Entity {
        let node = Entity()
        let cockpit = sphere(radius: 0.5, color: color)
        cockpit.scale = [1.3, 0.95, 0.95]
        cockpit.position = [0.25, 0.85, 0]
        node.addChild(cockpit)
        let boom = placeholderBox(color: color, size: [1.2, 0.14, 0.14])
        boom.position = [-0.75, 0.95, 0]
        node.addChild(boom)
        let fin = placeholderBox(color: color, size: [0.1, 0.4, 0.1])
        fin.position = [-1.3, 1.1, 0]
        node.addChild(fin)
        for z in [Float(-0.32), 0.32] {
            let skid = placeholderBox(color: PlatformColor(white: 0.25, alpha: 1),
                                      size: [1.0, 0.06, 0.06])
            skid.position = [0.2, 0.18, z]
            node.addChild(skid)
        }
        let mast = placeholderBox(color: PlatformColor(white: 0.25, alpha: 1),
                                  size: [0.08, 0.25, 0.08])
        mast.position = [0.25, 1.35, 0]
        node.addChild(mast)
        let rotorA = placeholderBox(color: PlatformColor(white: 0.2, alpha: 1),
                                    size: [1.9, 0.04, 0.14])
        rotorA.position = [0.25, 1.48, 0]
        node.addChild(rotorA)
        let rotorB = placeholderBox(color: PlatformColor(white: 0.2, alpha: 1),
                                    size: [0.14, 0.04, 1.9])
        rotorB.position = [0.25, 1.48, 0]
        node.addChild(rotorB)
        addEyes(to: node, atX: 0.8, y: 0.9)
        return node
    }

    /// A small, friendly NPC figure: a rounded body, a head, and two eyes facing
    /// forward (+z). Original placeholder geometry; a `\(modelRef).usdz` swaps it.
    static func character(modelRef: String? = nil, color: PlatformColor) -> Entity {
        characterRig(modelRef: modelRef, color: color).root
    }

    /// Like `character`, but keeps the eyes addressable (a `FaceRig` for blink +
    /// look) and returns the right-arm pivot so the engine can make the NPC wave —
    /// the Character Life pass (docs/tvos/GAME_DESIGN.md §4a). Arms hang from the
    /// shoulders as pivots, so rotating a pivot swings the whole arm.
    ///
    /// If `\(modelRef).usdz` is in the bundle it's returned as-is (it carries its
    /// own face/pose); the rig is empty and a dummy wave pivot is returned, so the
    /// engine's blink/look/wave animation safely no-ops on the real model.
    static func characterRig(modelRef: String? = nil, color: PlatformColor)
        -> (root: Entity, face: FaceRig, waveArm: Entity) {
        if let modelRef, let loaded = loadUSDZ(modelRef) {
            return (loaded, FaceRig(eyes: [], pupils: [], pupilRest: []), Entity())
        }
        let node = Entity()
        let body = placeholderBox(color: color, size: [0.5, 0.7, 0.42])
        body.position = [0, 0.35, 0]
        node.addChild(body)
        let head = sphere(radius: 0.26, color: color)
        head.position = [0, 0.92, 0]
        node.addChild(head)

        var eyes: [ModelEntity] = []
        var pupils: [ModelEntity] = []
        var rest: [SIMD3<Float>] = []
        for x in [Float(-0.1), 0.1] {
            let white = sphere(radius: 0.07, color: .white)
            white.position = [x, 0.96, 0.20]
            white.name = "eye"
            node.addChild(white)
            eyes.append(white)
            let pupil = sphere(radius: 0.032, color: PlatformColor(white: 0.1, alpha: 1))
            let p: SIMD3<Float> = [x, 0.96, 0.25]
            pupil.position = p
            pupil.name = "pupil"
            node.addChild(pupil)
            pupils.append(pupil)
            rest.append(p)
            let hi = sphere(radius: 0.014, color: .white)
            hi.position = [p.x + 0.01, p.y + 0.018, p.z + 0.02]
            node.addChild(hi)
        }

        // Rosy cheeks + a small grin so people look friendly too (face is on +z).
        for x in [Float(-0.17), 0.17] {
            let cheek = sphere(radius: 0.05,
                               color: PlatformColor(red: 1.0, green: 0.60, blue: 0.66, alpha: 0.92))
            cheek.scale = [1, 0.8, 0.28]
            cheek.position = [x, 0.88, 0.21]
            node.addChild(cheek)
        }
        for i in 0..<5 {
            let t = Float(i) / 4
            let u = (t - 0.5) * 2
            let bead = sphere(radius: 0.022,
                              color: PlatformColor(red: 0.30, green: 0.16, blue: 0.18, alpha: 1))
            bead.scale = [1, 1, 0.45]
            bead.position = [(t - 0.5) * 0.16, 0.84 + u * u * 0.04, 0.245]
            node.addChild(bead)
        }

        // Two little shoes so the figure stands rather than floats.
        for fx in [Float(-0.13), 0.13] {
            let foot = placeholderBox(color: PlatformColor(white: 0.22, alpha: 1), size: [0.18, 0.12, 0.28])
            foot.position = [fx, 0.06, 0.06]
            node.addChild(foot)
        }

        func arm(side: Float) -> Entity {
            let pivot = Entity()
            pivot.position = [side * 0.30, 0.58, 0.04]
            let limb = placeholderBox(color: color, size: [0.12, 0.34, 0.14])
            limb.position = [0, -0.17, 0]          // hang below the shoulder pivot
            pivot.addChild(limb)
            let hand = sphere(radius: 0.08, color: color)   // a rounded hand at the end
            hand.position = [0, -0.36, 0]
            pivot.addChild(hand)
            node.addChild(pivot)
            return pivot
        }
        _ = arm(side: -1)
        let waveArm = arm(side: 1)

        return (node, FaceRig(eyes: eyes, pupils: pupils, pupilRest: rest), waveArm)
    }

    /// A floating balloon collectible: a rounded body, a knot, and a string.
    /// Original placeholder geometry; swap a USDZ in later by id.
    static func balloon(color: PlatformColor) -> Entity {
        let node = Entity()
        let body = sphere(radius: 0.5, color: color)
        body.scale = [1, 1.18, 1]
        node.addChild(body)
        let knot = sphere(radius: 0.1, color: color)
        knot.position = [0, -0.55, 0]
        node.addChild(knot)
        let string = placeholderBox(color: PlatformColor(white: 0.96, alpha: 1), size: [0.03, 0.7, 0.03])
        string.position = [0, -0.95, 0]
        node.addChild(string)
        return node
    }

    /// A spinning coin collectible: a flattened gold disc with a brighter inset
    /// so it catches the eye as it turns.
    static func coin(color: PlatformColor) -> Entity {
        let node = Entity()
        let disc = sphere(radius: 0.45, color: color)
        disc.scale = [1, 1, 0.18]                     // flatten into a coin
        node.addChild(disc)
        let inset = sphere(radius: 0.30, color: PlatformColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1))
        inset.scale = [1, 1, 0.22]
        inset.position = [0, 0, 0.04]
        node.addChild(inset)
        return node
    }

    /// Parses `#rrggbb` (case-insensitive) into a platform color; nil if unparseable.
    static func color(hex: String?) -> PlatformColor? {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return PlatformColor(
            red: CGFloat((v >> 16) & 0xff) / 255.0,
            green: CGFloat((v >> 8) & 0xff) / 255.0,
            blue: CGFloat(v & 0xff) / 255.0,
            alpha: 1
        )
    }
}
#endif
