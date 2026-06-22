import CoreGraphics

/// A single screen ("square") of the world, authored as a readable text grid.
///
/// This is the whole point of the 2D pivot: a room is legible *as text* in the
/// source, so layout bugs are visible on the page instead of hidden in 3D
/// coordinates nobody ever rendered. Rows are top-to-bottom; each character is
/// one tile.
///
///   `#` wall   `B` bush   `T` tree   `.` floor   `A` Amelia's start (floor)
struct TileRoom {
    let rows: [String]

    var width: Int { rows.map { $0.count }.max() ?? 0 }
    var height: Int { rows.count }

    private func char(col: Int, row: Int) -> Character {
        guard row >= 0, row < height else { return "#" }
        let line = Array(rows[row])
        guard col >= 0, col < line.count else { return "#" }
        return line[col]
    }

    /// Solid tiles block movement. Off-grid reads as wall so the player can
    /// never leave the room (no harsh failure, just a soft stop).
    func isSolid(col: Int, row: Int) -> Bool {
        switch char(col: col, row: row) {
        case "#", "B", "T": return true
        default: return false
        }
    }

    /// Tile kind for rendering. Keeps render code free of grid parsing.
    enum Tile { case floor, wall, bush, tree, start }

    func tile(col: Int, row: Int) -> Tile {
        switch char(col: col, row: row) {
        case "#": return .wall
        case "B": return .bush
        case "T": return .tree
        case "A": return .start
        default: return .floor
        }
    }

    /// The `A` marker, in tile coordinates, where Amelia spawns.
    var start: (col: Int, row: Int) {
        for row in 0..<height {
            let line = Array(rows[row])
            if let col = line.firstIndex(of: "A") { return (col, row) }
        }
        return (width / 2, height / 2)
    }
}
