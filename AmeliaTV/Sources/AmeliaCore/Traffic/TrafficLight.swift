import Foundation

/// A traffic light that cycles green → yellow → red, used by the stop/go
/// teaching beat (docs/tvos/GAME_DESIGN.md §7). Cycle timing is ported from the
/// web prototype (drive/world.js): green 6s, yellow 2s, red 6s.
public struct TrafficLight: Equatable, Sendable {

    public enum State: String, Equatable, Sendable {
        case red, yellow, green
    }

    public let id: String
    public private(set) var state: State
    public let position: Vec2

    private var t: Double
    private let phase: Double
    private let greenDur: Double
    private let yellowDur: Double
    private let redDur: Double

    public init(id: String, position: Vec2 = .zero, phase: Double = 0,
                green: Double = 6, yellow: Double = 2, red: Double = 6) {
        self.id = id
        self.position = position
        self.phase = phase
        self.greenDur = green
        self.yellowDur = yellow
        self.redDur = red
        self.t = 0
        self.state = .green
        self.state = TrafficLight.stateFor(
            time: phase, green: green, yellow: yellow, red: red)
    }

    public var cycleLength: Double { greenDur + yellowDur + redDur }

    public mutating func update(dt: Double) {
        t += dt
        state = TrafficLight.stateFor(
            time: t + phase, green: greenDur, yellow: yellowDur, red: redDur)
    }

    /// Force the light into a state (used by scripted moments / tests).
    public mutating func set(_ state: State) { self.state = state }

    private static func stateFor(time: Double, green: Double, yellow: Double, red: Double) -> State {
        let total = green + yellow + red
        var c = time.truncatingRemainder(dividingBy: total)
        if c < 0 { c += total }
        if c < green { return .green }
        if c < green + yellow { return .yellow }
        return .red
    }
}
