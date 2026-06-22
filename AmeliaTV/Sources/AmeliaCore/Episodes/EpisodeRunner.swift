import Foundation

/// Where the bus is currently asked to drive (for navigation + the HUD beacon).
public struct EpisodeTarget: Equatable, Sendable {
    public var kind: Kind
    public var id: String
    public var position: Vec2
    public var radius: Double
    public var requireStop: Bool

    public enum Kind: String, Sendable { case place, light }

    public init(kind: Kind, id: String, position: Vec2, radius: Double, requireStop: Bool) {
        self.kind = kind
        self.id = id
        self.position = position
        self.radius = radius
        self.requireStop = requireStop
    }
}

/// Side effects the runner asks the rest of the game (and the app) to perform.
public enum EpisodeEvent: Equatable, Sendable {
    case speak(lineId: String, vars: [String: String])
    case setTarget(EpisodeTarget?)
    case board(passengerId: String)
    case drop(passengerId: String, placeId: String)
    case awaitChoice(promptLineId: String)
    case awaitFind(promptLineId: String, options: [FindOption])
    case starSparkle
    case reward(stars: Int, stickerId: String?)
    case completed
}

/// The world the runner observes to decide when to advance. Implemented by the
/// game session (and by a mock in tests) — the runner itself stays pure.
public protocol EpisodeWorld: AnyObject {
    var busPosition: Vec2 { get }
    var busSpeed: Double { get }
    func position(ofPlace placeId: String) -> Vec2?
    func position(ofLight lightId: String) -> Vec2?
    func lightState(_ lightId: String) -> TrafficLight.State
    /// Returns and consumes the most recent discrete left/right press (for choices).
    func consumeDiscreteTurn() -> InputIntents.DiscreteTurn
    /// Returns and consumes the id of the most recently tapped "spot it" option.
    func consumeFindAnswer() -> String?
}

public extension EpisodeWorld {
    // Default so existing worlds/tests that never use `find` need no changes.
    func consumeFindAnswer() -> String? { nil }
}

/// Plays an `Episode` beat by beat, emitting `EpisodeEvent`s. Driven by
/// `update(dt:)`. Generalizes drive/missions.js `Story` for the native game
/// (docs/tvos/GAME_DESIGN.md §2). There is no failure state: wrong choices and
/// missed stops are gently re-prompted, never punished.
public final class EpisodeRunner {
    public let episode: Episode
    private unowned let world: EpisodeWorld
    private let emit: (EpisodeEvent) -> Void

    // Tunables (defaults match the prototype's feel).
    public var arrivalRadius: Double = 12
    public var stopSpeed: Double = 2.2
    public var sayDwell: Double = 2.0
    public var boardDwell: Double = 2.2
    public var dropDwell: Double = 2.4
    /// If the child doesn't pick a turn at a fork within this long, the bus gently
    /// takes the correct one itself — so a young child can never get stuck (the
    /// no-harsh-failure / on-rails rule), while still being free to choose.
    public var autoChoiceDelay: Double = 5.0

    private var index = -1
    private var wait = 0.0
    private var arrived = false
    private var announcedArrive = false
    private var pendingArriveLine: String?
    private var lightStopped = false
    private var announcedRed = false
    private var promptedChoice = false
    private var choiceElapsed = 0.0
    public private(set) var finished = false

    public init(episode: Episode, world: EpisodeWorld, emit: @escaping (EpisodeEvent) -> Void) {
        self.episode = episode
        self.world = world
        self.emit = emit
    }

    public var currentBeatIndex: Int { index }

    public func start() {
        index = -1
        finished = false
        advance()
    }

    private func resetBeatFlags() {
        wait = 0
        arrived = false
        announcedArrive = false
        pendingArriveLine = nil
        lightStopped = false
        announcedRed = false
        promptedChoice = false
        choiceElapsed = 0
    }

    private func advance() {
        index += 1
        resetBeatFlags()
        guard index < episode.beats.count else {
            finish()
            return
        }
        switch episode.beats[index] {
        case let .say(lineId):
            emit(.speak(lineId: lineId, vars: [:]))
            wait = sayDwell

        case let .driveTo(placeId, arriveLineId):
            pendingArriveLine = arriveLineId
            if let pos = world.position(ofPlace: placeId) {
                emit(.setTarget(EpisodeTarget(kind: .place, id: placeId, position: pos,
                                              radius: arrivalRadius, requireStop: true)))
            }

        case let .pickup(passengerId, _):
            emit(.board(passengerId: passengerId))
            wait = boardDwell

        case let .dropoff(passengerId, placeId):
            emit(.drop(passengerId: passengerId, placeId: placeId))
            wait = dropDwell

        case let .lightStop(lightId):
            if let pos = world.position(ofLight: lightId) {
                emit(.setTarget(EpisodeTarget(kind: .light, id: lightId, position: pos,
                                              radius: arrivalRadius, requireStop: true)))
            }

        case let .choice(promptLineId, _):
            emit(.awaitChoice(promptLineId: promptLineId))
            emit(.speak(lineId: promptLineId, vars: [:]))
            promptedChoice = true

        case let .find(promptLineId, options, _):
            emit(.awaitFind(promptLineId: promptLineId, options: options))
            emit(.speak(lineId: promptLineId, vars: [:]))

        case .cutscene:
            wait = sayDwell

        case let .reward(stars, stickerId):
            emit(.setTarget(nil))
            emit(.reward(stars: stars, stickerId: stickerId))
            finish()
        }
    }

    private func finish() {
        finished = true
        emit(.setTarget(nil))
        emit(.completed)
    }

    public func update(dt: Double) {
        guard !finished, index >= 0, index < episode.beats.count else { return }
        if wait > 0 {
            wait -= dt
            if wait <= 0 { advance() }
            return
        }

        switch episode.beats[index] {
        case let .driveTo(placeId, _):
            guard let target = world.position(ofPlace: placeId) else { advance(); return }
            updateArrival(at: target, requireStop: true)

        case let .lightStop(lightId):
            guard let lp = world.position(ofLight: lightId) else { advance(); return }
            let near = world.busPosition.distance(to: lp) <= arrivalRadius
            guard near else { return }   // still driving to the light
            let stopped = abs(world.busSpeed) < stopSpeed
            switch world.lightState(lightId) {
            case .red:
                if stopped {
                    lightStopped = true
                    if !announcedRed { emit(.speak(lineId: "light.redStop", vars: [:])); announcedRed = true }
                }
            case .yellow:
                break
            case .green:
                if lightStopped {
                    emit(.speak(lineId: "light.goodStop", vars: [:]))
                    emit(.starSparkle)
                } else {
                    emit(.speak(lineId: "light.greenGo", vars: [:]))
                }
                advance()
            }

        case let .choice(_, correct):
            choiceElapsed += dt
            let turn = world.consumeDiscreteTurn()
            guard turn != .none else {
                // Never stuck: after a patient pause, the bus takes the right turn.
                if choiceElapsed >= autoChoiceDelay {
                    emit(.starSparkle)
                    advance()
                }
                return
            }
            let chosen: Beat.Turn = (turn == .left) ? .left : .right
            if chosen == correct {
                emit(.starSparkle)
                advance()
            } else {
                emit(.speak(lineId: "nav.tryOtherWay", vars: [:]))
            }

        case let .find(_, _, correctId):
            guard let answer = world.consumeFindAnswer() else { return }
            if answer == correctId {
                emit(.starSparkle)
                advance()
            } else {
                emit(.speak(lineId: "find.tryAgain", vars: [:]))   // gentle, no penalty
            }

        default:
            break
        }
    }

    private func updateArrival(at target: Vec2, requireStop: Bool) {
        let dist = world.busPosition.distance(to: target)
        let near = dist <= arrivalRadius
        if near && !announcedArrive {
            announcedArrive = true
            if let line = pendingArriveLine { emit(.speak(lineId: line, vars: [:])) }
        }
        let stoppedEnough = !requireStop || abs(world.busSpeed) < stopSpeed
        if near && stoppedEnough { advance() }
    }
}
