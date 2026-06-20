import Foundation

/// A turn instruction relative to the bus's current heading, used for spoken
/// cues and the big HUD arrow (docs/tvos/GAME_DESIGN.md §5).
public enum TurnCue: String, Equatable, Sendable {
    case straight, left, right, uTurn, arrive
}

/// The road network as a graph of intersections (nodes) and the roads between
/// them (edges). Navigation computes a path to a target and the next turn cue.
/// This generalizes the intersection grid sketched in drive/world.js into a
/// reusable, testable structure.
public struct RouteGraph: Sendable {

    public struct Node: Equatable, Sendable {
        public let id: String
        public let position: Vec2
        public init(id: String, position: Vec2) {
            self.id = id
            self.position = position
        }
    }

    private(set) var nodes: [String: Node] = [:]
    private(set) var adjacency: [String: Set<String>] = [:]

    public init() {}

    public mutating func addNode(_ id: String, at position: Vec2) {
        nodes[id] = Node(id: id, position: position)
        if adjacency[id] == nil { adjacency[id] = [] }
    }

    /// Adds a bidirectional road between two existing nodes.
    public mutating func addEdge(_ a: String, _ b: String) {
        guard nodes[a] != nil, nodes[b] != nil else { return }
        adjacency[a, default: []].insert(b)
        adjacency[b, default: []].insert(a)
    }

    public func position(of id: String) -> Vec2? { nodes[id]?.position }

    /// The node whose position is closest to `point`.
    public func nearestNode(to point: Vec2) -> String? {
        nodes.values.min(by: { $0.position.distance(to: point) < $1.position.distance(to: point) })?.id
    }

    /// Dijkstra shortest path (by Euclidean road length). Returns the ordered
    /// list of node ids from `start` to `goal`, or nil if unreachable.
    public func shortestPath(from start: String, to goal: String) -> [String]? {
        guard nodes[start] != nil, nodes[goal] != nil else { return nil }
        if start == goal { return [start] }

        var dist: [String: Double] = [start: 0]
        var prev: [String: String] = [:]
        var visited: Set<String> = []
        // Simple O(V^2) selection — graphs here are tiny.
        var frontier: Set<String> = [start]

        while !frontier.isEmpty {
            let u = frontier.min(by: { (dist[$0] ?? .infinity) < (dist[$1] ?? .infinity) })!
            frontier.remove(u)
            if u == goal { break }
            visited.insert(u)
            let up = nodes[u]!.position
            for v in adjacency[u] ?? [] where !visited.contains(v) {
                let alt = (dist[u] ?? .infinity) + up.distance(to: nodes[v]!.position)
                if alt < (dist[v] ?? .infinity) {
                    dist[v] = alt
                    prev[v] = u
                    frontier.insert(v)
                }
            }
        }

        guard dist[goal] != nil else { return nil }
        var path: [String] = [goal]
        var cur = goal
        while let p = prev[cur] {
            path.append(p)
            cur = p
            if p == start { break }
        }
        return path.reversed()
    }

    /// The turn cue for travelling from the bus (at `position`, facing `heading`
    /// radians where 0 = +x and increasing = right, matching the driving model)
    /// toward `nextNode`. `arriveRadius` decides when we've effectively arrived.
    public func turnCue(at position: Vec2, heading: Double, toward nextNode: String,
                        arriveRadius: Double = 8) -> TurnCue {
        guard let target = nodes[nextNode]?.position else { return .straight }
        let to = target - position
        if to.length <= arriveRadius { return .arrive }
        let bearing = atan2(to.z, to.x)
        let delta = RouteGraph.normalize(bearing - heading)
        let straightBand = 0.35   // ~20°
        let uTurnBand = 2.6       // ~150°+
        if abs(delta) <= straightBand { return .straight }
        if abs(delta) >= uTurnBand { return .uTurn }
        // heading increases to the right, so a positive delta means turn right.
        return delta > 0 ? .right : .left
    }

    /// Normalizes an angle to (-π, π].
    static func normalize(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }
}
