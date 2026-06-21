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
    /// Optional effects/music. Like the speaker, the app supplies a procedural
    /// AVAudioEngine; tests pass a spy (or nil). Audio is never required for play.
    private let sound: SoundPlayer?

    // World state
    private var graph: RouteGraph
    private var lights: [String: TrafficLight]
    private var runner: EpisodeRunner?
    private var pendingTurn: InputIntents.DiscreteTurn = .none
    private var collectedIds: Set<String> = []

    /// How close the bus must pass to scoop a collectible (world units). Generous,
    /// because a young child only nudges toward it (no failure for a near miss).
    private let collectibleRadius: Double = 9

    // Observable-ish state for the HUD / renderer
    public private(set) var currentTarget: EpisodeTarget?
    public private(set) var currentTurnCue: TurnCue = .straight
    public private(set) var currentPassengerId: String?
    public private(set) var awaitingChoice = false
    public private(set) var sparkleCount = 0
    /// Collectibles scooped this run (each also awards its stars).
    public private(set) var collectedCount = 0
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

    /// The stars + sticker the active episode awards on completion, read straight
    /// from its `reward` beat. Lets the reward screen (A2-12) show what was earned
    /// without hardcoding it — same data-driven pattern as `passengerPlan`.
    public struct RewardPlan: Equatable, Sendable {
        public let stars: Int
        public let stickerId: String?
        public init(stars: Int, stickerId: String?) {
            self.stars = stars
            self.stickerId = stickerId
        }
    }

    public var rewardPlan: RewardPlan? {
        guard let id = activeEpisodeId,
              let episode = content.episodes.first(where: { $0.id == id }) else { return nil }
        for beat in episode.beats {
            if case let .reward(stars, stickerId) = beat {
                return RewardPlan(stars: stars, stickerId: stickerId)
            }
        }
        return nil
    }

    public var language: Language {
        get { dialogue.language }
        set { dialogue.language = newValue; save.language = newValue }
    }

    public init(content: GameContent, save: SaveSlot,
                speaker: LineSpeaker? = nil,
                sound: SoundPlayer? = nil,
                persist: ((SaveSlot) -> Void)? = nil) {
        self.content = content
        self.save = save
        self.persist = persist
        self.sound = sound
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
        collectedCount = 0
        collectedIds.removeAll()
        currentPassengerId = nil
        currentTarget = nil
        awaitingChoice = false
        core.assistLevel = save.assistLevel
        core.reset(to: start, heading: heading)
        dialogue.clear()
        sound?.setMusic(.driving)
        sound?.play(.horn)
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
            cue(forLine: lineId)
        case let .setTarget(target):
            currentTarget = target
            awaitingChoice = false
        case let .board(passengerId):
            currentPassengerId = passengerId
            sound?.play(.doorOpen)
        case .drop:
            currentPassengerId = nil
            sound?.play(.doorClose)
        case .awaitChoice:
            awaitingChoice = true
        case .starSparkle:
            sparkleCount += 1
            save.award(stars: 1)
            sound?.play(.starSparkle)
        case let .reward(stars, stickerId):
            save.award(stars: stars)
            sound?.play(.reward)
            if let s = stickerId { save.grant(sticker: s); sound?.play(.rewardSticker) }
        case .completed:
            if let id = activeEpisodeId { save.markComplete(episode: id) }
            finished = true
            currentTarget = nil
            awaitingChoice = false
            sound?.setMusic(.reward)
            persist?(save)
        }
    }

    /// Maps a few spoken lines to a matching effect so the world chimes when a
    /// light goes green / a stop is praised, and gives a soft non-punishing bump
    /// when the child is nudged to try the other way at a fork. Other lines play
    /// no effect (the voice carries them).
    private func cue(forLine lineId: String) {
        switch lineId {
        case "light.greenGo", "light.goodStop":
            sound?.play(.chime)
        case "nav.tryOtherWay":
            sound?.play(.bump)
        default:
            break
        }
    }

    // MARK: - Per-frame update

    /// Advance the whole session by `dt`, given the latest player input.
    public func tick(dt: Double, input: InputIntents = .neutral) {
        guard dt > 0 else { return }

        // Latch a discrete turn for the episode runner (choices).
        if input.discreteTurn != .none { pendingTurn = input.discreteTurn }

        // The child can honk for a friendly toot any time (edge-triggered input).
        if input.honkPressed { sound?.play(.horn) }

        // Lights.
        for key in lights.keys { lights[key]?.update(dt: dt) }

        // Auto-drive toward the current target (when the assist level drives).
        applyAutoDrive()

        // Physics + episode logic.
        core.tick(dt: dt, input: input)
        runner?.update(dt: dt)

        // Scoop any collectible the bus just drove near.
        collectPickups()

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

    // MARK: - Collectibles

    /// Scoops every uncollected collectible the bus is currently near, awarding
    /// its stars. Pure proximity — no aiming required, and missing one is fine.
    private func collectPickups() {
        guard !content.collectibles.isEmpty else { return }
        let p = core.bus.position
        for c in content.collectibles where !collectedIds.contains(c.id) {
            if c.position.vec.distance(to: p) <= collectibleRadius {
                collectedIds.insert(c.id)
                collectedCount += 1
                save.award(stars: c.reward)
            }
        }
    }

    /// Whether a given collectible has been scooped (for the renderer to hide it).
    public func isCollected(_ id: String) -> Bool { collectedIds.contains(id) }

    // MARK: - Lookups for the renderer

    public func lightSnapshot() -> [TrafficLight] { Array(lights.values) }
    public func place(_ id: String) -> Place? { content.places.first(where: { $0.id == id }) }
    public func passenger(_ id: String) -> Passenger? {
        content.passengers.first(where: { $0.id == id })
    }
}
