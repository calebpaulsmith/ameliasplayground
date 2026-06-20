import Foundation

/// Ties the Game Core together for a playable episode: driving + assist,
/// the episode runner, traffic lights, navigation, dialogue, and rewards.
///
/// It is rendering-agnostic (no RealityKit/SwiftUI/AVFoundation) and conforms to
/// `EpisodeWorld`, so a full playthrough can be unit-tested headlessly. The app
/// supplies a `LineSpeaker` (AVSpeech) and renders/observes the published state.
/// See docs/tvos/TECHNICAL_ARCHITECTURE.md (high-level architecture).
public final class GameSession: EpisodeWorld {

    // Inputs / collaborators
    public let content: GameContent
    public let dialogue: DialogueDirector
    public let core: GameCore
    public private(set) var save: SaveSlot
    private let persist: ((SaveSlot) -> Void)?

    // World state
    private var graph: RouteGraph
    private var lights: [String: TrafficLight]
    private var runner: EpisodeRunner?
    private var pendingTurn: InputIntents.DiscreteTurn = .none

    // Observable-ish state for the HUD / renderer
    public private(set) var currentTarget: EpisodeTarget?
    public private(set) var currentTurnCue: TurnCue = .straight
    public private(set) var currentPassengerId: String?
    public private(set) var awaitingChoice = false
    public private(set) var sparkleCount = 0
    public private(set) var finished = false
    public private(set) var activeEpisodeId: String?

    public var subtitle: String { dialogue.currentSubtitle }
    public var bus: GameCore.BusState { core.bus }

    /// Big, single-glance guidance for the HUD. `stop` only when the bus is being
    /// asked to hold at a red light it must obey; `go` otherwise. Derived from core
    /// state so the HUD stays a thin, testable reflection of the game (A2-10).
    public enum DrivePrompt: String, Sendable { case go, stop }

    public var drivePrompt: DrivePrompt {
        guard let target = currentTarget, target.kind == .light, target.requireStop else {
            return .go
        }
        let dist = (target.position - core.bus.position).length
        if dist <= target.radius + 6, lightState(target.id) == .red { return .stop }
        return .go
    }

    /// The string id naming the current destination, for the HUD beacon label.
    /// Lights have no friendly name, so only places resolve.
    public var currentTargetNameId: String? {
        guard let target = currentTarget, target.kind == .place else { return nil }
        return place(target.id)?.nameId
    }

    /// Who the active episode picks up and where, for the renderer to place the
    /// waiting/riding/dropped passenger. Derived from the episode's beats so the
    /// presentation stays data-driven (A2-09).
    public struct PassengerPlan: Equatable, Sendable {
        public let passengerId: String
        public let pickupPlaceId: String
        public let dropoffPlaceId: String
    }

    public var passengerPlan: PassengerPlan? {
        guard let id = activeEpisodeId,
              let episode = content.episodes.first(where: { $0.id == id }) else { return nil }
        var passengerId: String?
        var pickup: String?
        var dropoff: String?
        for beat in episode.beats {
            switch beat {
            case let .pickup(pid, atStop):
                if passengerId == nil { passengerId = pid }
                if pickup == nil { pickup = atStop }
            case let .dropoff(pid, placeId):
                if passengerId == nil { passengerId = pid }
                dropoff = placeId
            default:
                break
            }
        }
        guard let pid = passengerId, let pu = pickup, let dp = dropoff else { return nil }
        return PassengerPlan(passengerId: pid, pickupPlaceId: pu, dropoffPlaceId: dp)
    }
    public var language: Language {
        get { dialogue.language }
        set { dialogue.language = newValue; save.language = newValue }
    }

    public init(content: GameContent, save: SaveSlot,
                speaker: LineSpeaker? = nil,
                persist: ((SaveSlot) -> Void)? = nil) {
        self.content = content
        self.save = save
        self.persist = persist
        self.core = GameCore(save: save)
        self.dialogue = DialogueDirector(localizer: content.localizer,
                                         language: save.language, speaker: speaker)
        self.lights = Dictionary(uniqueKeysWithValues: content.lights.map {
            ($0.id, TrafficLight(id: $0.id, position: $0.position.vec, phase: $0.phase ?? 0))
        })
        self.graph = GameSession.buildGraph(from: content)
    }

    /// Builds a simple route graph linking every place and light so navigation
    /// has a connected network. For the small slice world a fully-connected set
    /// of waypoints is sufficient; richer road graphs come with real neighborhoods.
    private static func buildGraph(from content: GameContent) -> RouteGraph {
        var g = RouteGraph()
        for p in content.places { g.addNode("place:\(p.id)", at: p.position.vec) }
        for l in content.lights { g.addNode("light:\(l.id)", at: l.position.vec) }
        let ids = Array(g.nodes.keys)
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count { g.addEdge(ids[i], ids[j]) }
        }
        return g
    }

    // MARK: - Episode lifecycle

    public func start(episodeId: String, at start: Vec2 = .zero, heading: Double = 0) {
        guard let episode = content.episodes.first(where: { $0.id == episodeId }) else { return }
        activeEpisodeId = episodeId
        finished = false
        sparkleCount = 0
        currentPassengerId = nil
        currentTarget = nil
        awaitingChoice = false
        core.assistLevel = save.assistLevel
        core.reset(to: start, heading: heading)
        dialogue.clear()
        let r = EpisodeRunner(episode: episode, world: self) { [weak self] event in
            self?.handle(event)
        }
        runner = r
        r.start()
    }

    private func handle(_ event: EpisodeEvent) {
        switch event {
        case let .speak(lineId, vars):
            dialogue.play(lineId, vars: vars)
        case let .setTarget(target):
            currentTarget = target
            awaitingChoice = false
        case let .board(passengerId):
            currentPassengerId = passengerId
        case .drop:
            currentPassengerId = nil
        case .awaitChoice:
            awaitingChoice = true
        case .starSparkle:
            sparkleCount += 1
            save.award(stars: 1)
        case let .reward(stars, stickerId):
            save.award(stars: stars)
            if let s = stickerId { save.grant(sticker: s) }
        case .completed:
            if let id = activeEpisodeId { save.markComplete(episode: id) }
            finished = true
            currentTarget = nil
            awaitingChoice = false
            persist?(save)
        }
    }

    // MARK: - Per-frame update

    /// Advance the whole session by `dt`, given the latest player input.
    public func tick(dt: Double, input: InputIntents = .neutral) {
        guard dt > 0 else { return }

        // Latch a discrete turn for the episode runner (choices).
        if input.discreteTurn != .none { pendingTurn = input.discreteTurn }

        // Lights.
        for key in lights.keys { lights[key]?.update(dt: dt) }

        // Auto-drive toward the current target (when the assist level drives).
        applyAutoDrive()

        // Physics + episode logic.
        core.tick(dt: dt, input: input)
        runner?.update(dt: dt)

        // Refresh the HUD turn cue.
        currentTurnCue = computeTurnCue()
    }

    private func applyAutoDrive() {
        guard core.assistLevel.autoDrives else {
            core.autoThrottle = 0; core.autoBrake = 0; core.autoSteer = 0
            return
        }
        guard let target = currentTarget else {
            // No target: gently hold position.
            core.autoThrottle = 0; core.autoBrake = 1; core.autoSteer = 0
            return
        }
        let toTarget = target.position - core.bus.position
        let dist = toTarget.length
        let desired = atan2(toTarget.z, toTarget.x)
        let err = RouteGraph.normalize(desired - core.bus.heading)
        core.autoSteer = (err / (.pi / 4)).clamped(to: -1 ... 1)
        if dist > target.radius {
            core.autoThrottle = 1; core.autoBrake = 0
        } else {
            // Arrived zone: stop so `requireStop` arrivals are satisfied.
            core.autoThrottle = 0; core.autoBrake = 1
        }
    }

    private func computeTurnCue() -> TurnCue {
        guard let target = currentTarget else { return .straight }
        let to = target.position - core.bus.position
        if to.length <= 8 { return .arrive }
        let bearing = atan2(to.z, to.x)
        let delta = RouteGraph.normalize(bearing - core.bus.heading)
        if abs(delta) <= 0.35 { return .straight }
        if abs(delta) >= 2.6 { return .uTurn }
        return delta > 0 ? .right : .left
    }

    // MARK: - EpisodeWorld

    public var busPosition: Vec2 { core.bus.position }
    public var busSpeed: Double { core.bus.speed }
    public func position(ofPlace placeId: String) -> Vec2? {
        content.places.first(where: { $0.id == placeId })?.position.vec
    }
    public func position(ofLight lightId: String) -> Vec2? { lights[lightId]?.position }
    public func lightState(_ lightId: String) -> TrafficLight.State { lights[lightId]?.state ?? .green }
    public func consumeDiscreteTurn() -> InputIntents.DiscreteTurn {
        defer { pendingTurn = .none }
        return pendingTurn
    }

    // MARK: - Lookups for the renderer

    public func lightSnapshot() -> [TrafficLight] { Array(lights.values) }
    public func place(_ id: String) -> Place? { content.places.first(where: { $0.id == id }) }
    public func passenger(_ id: String) -> Passenger? {
        content.passengers.first(where: { $0.id == id })
    }
}
