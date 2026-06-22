import Foundation
import SpriteKit

#if canImport(GameController)
import GameController
#endif

/// The first visible thing in the 2D game: one top-down room you can walk
/// around. Amelia moves, the bushes sway, and walls/bushes/trees stop her
/// (tile collision) so nothing clips through anything.
///
/// Deliberately small. The point of this slice is the *feedback loop*: when CI
/// records this scene, we can finally SEE whether the camera, placement, and
/// collision are right — the exact things that went wrong, unseen, in 3D.
final class RoomScene: SKScene {

    // The room, authored as text (see TileRoom). Easy to read, easy to fix.
    private let room = TileRoom(rows: [
        "###############",
        "#.............#",
        "#..B.......B..#",
        "#.....T.......#",
        "#......A......#",
        "#..B.......T..#",
        "#.............#",
        "#....B...B....#",
        "###############",
    ])

    private var tileSize: CGFloat = 64
    private var gridOrigin: CGPoint = .zero      // bottom-left of the grid, in scene points
    private let world = SKNode()
    private let player = SKNode()
    private var playerRadius: CGFloat = 22

    private var lastUpdate: TimeInterval = 0
    private var inputActive = false              // a real controller has taken over

    // Demo "attract" walk so the CI recording shows motion + a collision bump,
    // with no human at the controller. Waypoints are in tile coords.
    private let demoPath: [(col: Int, row: Int)] = [
        (3, 4), (3, 7), (8, 7), (11, 4), (8, 2), (5, 3), (7, 4),
    ]
    private var demoIndex = 0
    private var demoWaitedOnWaypoint: TimeInterval = 0

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.46, green: 0.73, blue: 0.42, alpha: 1) // grassy
        anchorPoint = .zero
        layoutGrid()
        buildRoom()
        buildPlayer()
        addChild(world)
    }

    // MARK: - Layout

    private func layoutGrid() {
        let cols = CGFloat(room.width)
        let rows = CGFloat(room.height)
        // Fit the whole room on screen with a little margin.
        let margin: CGFloat = 0.92
        tileSize = min(size.width * margin / cols, size.height * margin / rows)
        playerRadius = tileSize * 0.34
        let gridW = tileSize * cols
        let gridH = tileSize * rows
        gridOrigin = CGPoint(x: (size.width - gridW) / 2, y: (size.height - gridH) / 2)
    }

    /// Center point (in scene space) of a tile. Row 0 is the TOP row.
    private func center(col: Int, row: Int) -> CGPoint {
        let x = gridOrigin.x + (CGFloat(col) + 0.5) * tileSize
        let y = gridOrigin.y + (CGFloat(room.height - 1 - row) + 0.5) * tileSize
        return CGPoint(x: x, y: y)
    }

    /// Which tile a scene point falls in.
    private func tileAt(_ p: CGPoint) -> (col: Int, row: Int) {
        let col = Int((p.x - gridOrigin.x) / tileSize)
        let rowFromBottom = Int((p.y - gridOrigin.y) / tileSize)
        let row = room.height - 1 - rowFromBottom
        return (col, row)
    }

    private func isSolid(at p: CGPoint) -> Bool {
        // Sample the player's footprint at four edge points so she stops at the
        // tile face instead of sinking halfway in.
        let r = playerRadius * 0.8
        for off in [CGPoint(x: r, y: 0), CGPoint(x: -r, y: 0),
                    CGPoint(x: 0, y: r), CGPoint(x: 0, y: -r)] {
            let t = tileAt(CGPoint(x: p.x + off.x, y: p.y + off.y))
            if room.isSolid(col: t.col, row: t.row) { return true }
        }
        return false
    }

    // MARK: - Building nodes

    private func buildRoom() {
        for row in 0..<room.height {
            for col in 0..<room.width {
                let c = center(col: col, row: row)
                switch room.tile(col: col, row: row) {
                case .wall:
                    world.addChild(rect(at: c, color: SKColor(red: 0.55, green: 0.45, blue: 0.38, alpha: 1)))
                case .floor, .start:
                    world.addChild(rect(at: c, color: SKColor(red: 0.52, green: 0.78, blue: 0.47, alpha: 1), inset: 1))
                case .bush:
                    world.addChild(rect(at: c, color: SKColor(red: 0.52, green: 0.78, blue: 0.47, alpha: 1), inset: 1))
                    world.addChild(bush(at: c))
                case .tree:
                    world.addChild(rect(at: c, color: SKColor(red: 0.52, green: 0.78, blue: 0.47, alpha: 1), inset: 1))
                    world.addChild(tree(at: c))
                }
            }
        }
    }

    private func rect(at c: CGPoint, color: SKColor, inset: CGFloat = 0) -> SKSpriteNode {
        let n = SKSpriteNode(color: color, size: CGSize(width: tileSize - inset, height: tileSize - inset))
        n.position = c
        n.zPosition = 0
        return n
    }

    private func bush(at c: CGPoint) -> SKNode {
        let r = tileSize * 0.38
        let b = SKShapeNode(circleOfRadius: r)
        b.fillColor = SKColor(red: 0.20, green: 0.55, blue: 0.25, alpha: 1)
        b.strokeColor = SKColor(red: 0.13, green: 0.40, blue: 0.18, alpha: 1)
        b.lineWidth = 3
        b.position = c
        b.zPosition = 5
        // Gentle sway, randomized so they don't pulse in unison.
        let phase = Double.random(in: 0...0.8)
        let sway = SKAction.sequence([
            SKAction.scaleX(to: 1.06, y: 0.96, duration: 0.9),
            SKAction.scaleX(to: 0.96, y: 1.05, duration: 0.9),
        ])
        sway.timingMode = .easeInEaseOut
        b.run(SKAction.sequence([SKAction.wait(forDuration: phase),
                                 SKAction.repeatForever(sway)]))
        return b
    }

    private func tree(at c: CGPoint) -> SKNode {
        let node = SKNode()
        node.position = c
        node.zPosition = 6
        let trunk = SKSpriteNode(color: SKColor(red: 0.45, green: 0.30, blue: 0.18, alpha: 1),
                                 size: CGSize(width: tileSize * 0.18, height: tileSize * 0.40))
        trunk.position = CGPoint(x: 0, y: -tileSize * 0.18)
        let crown = SKShapeNode(circleOfRadius: tileSize * 0.40)
        crown.fillColor = SKColor(red: 0.16, green: 0.47, blue: 0.22, alpha: 1)
        crown.strokeColor = SKColor(red: 0.10, green: 0.34, blue: 0.15, alpha: 1)
        crown.lineWidth = 3
        crown.position = CGPoint(x: 0, y: tileSize * 0.10)
        node.addChild(trunk)
        node.addChild(crown)
        return node
    }

    private func buildPlayer() {
        let body = SKShapeNode(circleOfRadius: playerRadius)
        body.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
        body.strokeColor = SKColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 1)
        body.lineWidth = 3
        // A little face so she reads as a character, not a dot.
        for dx in [-playerRadius * 0.35, playerRadius * 0.35] {
            let eye = SKShapeNode(circleOfRadius: playerRadius * 0.14)
            eye.fillColor = .black
            eye.strokeColor = .clear
            eye.position = CGPoint(x: dx, y: playerRadius * 0.18)
            body.addChild(eye)
        }
        player.addChild(body)
        player.zPosition = 10
        let s = room.start
        player.position = center(col: s.col, row: s.row)
        world.addChild(player)
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime
        guard dt > 0 else { return }

        let dir = currentDirection(dt: dt)
        let speed = tileSize * 5.5     // tiles/sec, scaled to tile size
        let step = CGVector(dx: dir.dx * speed * CGFloat(dt),
                            dy: dir.dy * speed * CGFloat(dt))

        // Move per-axis so she slides along walls instead of sticking.
        var pos = player.position
        let tryX = CGPoint(x: pos.x + step.dx, y: pos.y)
        if !isSolid(at: tryX) { pos.x = tryX.x }
        let tryY = CGPoint(x: pos.x, y: pos.y + step.dy)
        if !isSolid(at: tryY) { pos.y = tryY.y }

        // Walking bob.
        if abs(step.dx) + abs(step.dy) > 0.1 {
            let bob = 1 + 0.04 * CGFloat(sin(currentTime * 12))
            player.yScale = bob
        } else {
            player.yScale = 1
        }
        player.position = pos
    }

    /// Player input if a controller is connected, otherwise the demo walk.
    private func currentDirection(dt: TimeInterval) -> CGVector {
        if let d = controllerDirection() {
            inputActive = true
            return normalized(d)
        }
        if inputActive { return .zero }   // player paused; don't auto-wander
        return demoDirection(dt: dt)
    }

    private func demoDirection(dt: TimeInterval) -> CGVector {
        guard !demoPath.isEmpty else { return .zero }
        let target = center(col: demoPath[demoIndex].col, row: demoPath[demoIndex].row)
        let v = CGVector(dx: target.x - player.position.x, dy: target.y - player.position.y)
        let dist = hypot(v.dx, v.dy)

        // Advance when we arrive, or after a short timeout (e.g. a bush blocks
        // the straight line) so the demo never gets permanently stuck.
        demoWaitedOnWaypoint += dt
        if dist < tileSize * 0.25 || demoWaitedOnWaypoint > 3.0 {
            demoIndex = (demoIndex + 1) % demoPath.count
            demoWaitedOnWaypoint = 0
            return .zero
        }
        return normalized(v)
    }

    private func normalized(_ v: CGVector) -> CGVector {
        let m = hypot(v.dx, v.dy)
        return m < 0.0001 ? .zero : CGVector(dx: v.dx / m, dy: v.dy / m)
    }

    private func controllerDirection() -> CGVector? {
        #if canImport(GameController)
        for c in GCController.controllers() {
            if let g = c.extendedGamepad {
                let s = g.leftThumbstick
                if abs(s.xAxis.value) > 0.12 || abs(s.yAxis.value) > 0.12 {
                    return CGVector(dx: CGFloat(s.xAxis.value), dy: CGFloat(s.yAxis.value))
                }
                let d = g.dpad
                if abs(d.xAxis.value) > 0.12 || abs(d.yAxis.value) > 0.12 {
                    return CGVector(dx: CGFloat(d.xAxis.value), dy: CGFloat(d.yAxis.value))
                }
            } else if let m = c.microGamepad {
                m.reportsAbsoluteDpadValues = true
                let d = m.dpad
                if abs(d.xAxis.value) > 0.12 || abs(d.yAxis.value) > 0.12 {
                    return CGVector(dx: CGFloat(d.xAxis.value), dy: CGFloat(d.yAxis.value))
                }
            }
        }
        #endif
        return nil
    }
}
