import Foundation

/// A tiny deterministic LCG (same constants as the renderer's rooftop detail RNG)
/// so the streetwall is reproducible **fixed data** — not reshuffled every launch,
/// which is what broke CI-capture comparability with the old random fill.
struct DeterministicRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    /// A value in `0..<n`.
    mutating func index(_ n: Int) -> Int { Int((next() >> 33) % UInt64(n)) }
    mutating func pick<T>(_ a: [T]) -> T { a[index(a.count)] }
}

public extension WorldLayout {
    /// The Welles streetwall — side-by-side frontage buildings filling the three
    /// drivable frontages around the park block, leaving gaps at the cross streets
    /// and skipping the hand-placed landmarks.
    ///
    /// Authored as a **deterministic** generator (seeded), so the output is
    /// fixed/reproducible data: readable, validatable by `WorldValidator`, and
    /// stable across CI captures — replacing the renderer's old per-launch random
    /// fill (which reshuffled every run). The frontage geometry, building-size
    /// menu, cross-street gaps, and overlap-avoidance mirror the old `streetRow`.
    static var wellesStreetwall: [BuildingFootprint] {
        let setback = 55.0 + 46.0 + 40.0            // 141 (matches TownScene.buildingSetback)
        let cross = [-800.0, -130.0, 550.0]         // cross streets cut the block — leave gaps
        let widths = [150.0, 170.0, 190.0, 210.0]
        let depths = [130.0, 140.0, 160.0]
        let heights = [70.0, 90.0, 110.0, 130.0]
        let gaps = [8.0, 10.0, 38.0]

        // Avoid the landmarks (anchors + church + corner restaurant). The library is
        // far east of every frontage, so it's irrelevant here.
        let avoid = welles.buildings.filter { $0.id != "library" }
        var rng = DeterministicRNG(seed: 0x57_2EE7_5EED)   // "street seed"
        var result: [BuildingFootprint] = []

        func free(_ c: Vec2, _ w: Double, _ d: Double) -> Bool {
            let cand = BuildingFootprint(id: "", center: c, width: w, depth: d, kind: .shop)
            for f in avoid where cand.overlaps(f, padding: 12) { return false }
            for f in result where cand.overlaps(f, padding: 12) { return false }
            return true
        }

        func row(horizontal: Bool, frontEdge: Double, from: Double, to: Double, tag: String) {
            var p = from
            var i = 0
            while p < to {
                let w = rng.pick(widths), depth = rng.pick(depths)
                let along = p + w / 2
                if cross.contains(where: { abs($0 - along) < w / 2 + 70 }) { p += 90; continue }
                let center = horizontal
                    ? Vec2(along, frontEdge < 0 ? frontEdge - depth / 2 : frontEdge + depth / 2)
                    : Vec2(frontEdge - depth / 2, along)
                if free(center, w, depth) {
                    let kind: BuildingKind = rng.index(4) == 0 ? .shop : .apartments
                    let height = rng.pick(heights)
                    result.append(BuildingFootprint(id: "wall-\(tag)-\(i)", center: center,
                                                    width: w, depth: depth, height: height, kind: kind))
                    i += 1
                }
                p += w + rng.pick(gaps)
            }
        }

        row(horizontal: true,  frontEdge: -700 - setback, from: -1230, to: 470, tag: "n")  // north
        row(horizontal: true,  frontEdge:  700 + setback, from: -1230, to: 720, tag: "s")  // south
        row(horizontal: false, frontEdge: -800 - setback, from: -600,  to: 600, tag: "w")  // west
        return result
    }

    /// The full Welles town — landmarks + streetwall. The complete authored layout
    /// the `WorldValidator` checks and the renderer draws.
    static var wellesComplete: WorldLayout {
        var layout = welles
        layout.buildings += wellesStreetwall
        return layout
    }
}
