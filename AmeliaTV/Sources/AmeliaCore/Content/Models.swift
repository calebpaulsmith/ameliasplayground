import Foundation

/// Data-driven content types. These decode the JSON in AmeliaTV/Content/ and are
/// validated against AmeliaTV/Content/schema/ in CI. Everything player-facing is
/// a string id (resolved via Localizer), never a hardcoded sentence.
/// See docs/tvos/TECHNICAL_ARCHITECTURE.md "Data model".

/// A 2D point on the ground plane, as authored in content JSON.
public struct Point2D: Codable, Equatable, Sendable {
    public var x: Double
    public var z: Double
    public init(x: Double, z: Double) { self.x = x; self.z = z }
    public var vec: Vec2 { Vec2(x, z) }
}

/// A named location in the world (garage, park, school, ...).
public struct Place: Codable, Equatable, Sendable {
    public var id: String
    public var nameId: String          // string id, resolved per language
    public var kind: String            // "garage" | "park" | "school" | ...
    public var position: Point2D
    public var beaconColor: String?    // hex like "#57b85a"
}

/// A traffic light placed in the world, referenced by `lightStop` beats.
public struct Light: Codable, Equatable, Sendable {
    public var id: String
    public var position: Point2D
    public var phase: Double?
}

/// A light, optional pick-up scattered along a route — a balloon or coin the
/// child can drift a touch to scoop. Feeds the star economy and rewards
/// curiosity; **never required** (missing one is no failure). Authored as data so
/// routes can be seeded with delight without code (docs/tvos/MODES_AND_DIRECTION.md
/// — the "Agency pass").
public struct Collectible: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String            // "balloon" | "coin" | ...
    public var position: Point2D
    public var color: String?          // hex tint; nil → the kind's default
    public var stars: Int?             // reward when scooped; nil → 1

    public init(id: String, kind: String, position: Point2D,
                color: String? = nil, stars: Int? = nil) {
        self.id = id
        self.kind = kind
        self.position = position
        self.color = color
        self.stars = stars
    }

    /// Stars granted on pickup (defaults to 1).
    public var reward: Int { max(0, stars ?? 1) }
}

/// A passenger / animal friend.
public struct Passenger: Codable, Equatable, Sendable {
    public var id: String
    public var nameId: String
    public var homePlace: String       // Place.id
    public var color: String           // hex
    public var modelRef: String        // model id (placeholder fallback if absent)
    public var lineIds: [String]       // greeting/chatter/thanks string ids
}

/// A friendly vehicle character — e.g. the original Rescue Team (fire truck,
/// tow truck, ambulance, rescue helicopter). Set dressing / future episode cast,
/// authored as data. Original designs only (RISKS_AND_DECISIONS.md D-IP-1).
public struct Vehicle: Codable, Equatable, Sendable {
    public var id: String
    public var nameId: String
    public var role: String            // "fire" | "tow" | "ambulance" | "helicopter" | ...
    public var color: String           // hex
    public var modelRef: String        // model id (placeholder fallback if absent)
    public var homePlace: String       // Place.id where it idles
    public var lineIds: [String]?      // optional chatter string ids
}

/// One step of an episode. Tagged union mirroring drive/missions.js beats,
/// generalized for the native game (see GAME_DESIGN.md §2).
/// One tappable answer in a `find` ("spot it!") beat. Presentation-light and
/// data-driven: an optional colour swatch, an optional SF-Symbol icon, and an
/// optional bilingual label — the renderer shows whatever is provided.
public struct FindOption: Codable, Equatable, Sendable {
    public var id: String
    public var color: String?      // hex swatch, e.g. "#ff5e7a"
    public var iconId: String?     // SF Symbol name, e.g. "car.fill"
    public var labelId: String?    // bilingual string id for a caption

    public init(id: String, color: String? = nil, iconId: String? = nil, labelId: String? = nil) {
        self.id = id
        self.color = color
        self.iconId = iconId
        self.labelId = labelId
    }
}

public enum Beat: Codable, Equatable, Sendable {
    case say(lineId: String)
    case driveTo(placeId: String, arriveLineId: String?)
    case pickup(passengerId: String, atStop: String)
    case dropoff(passengerId: String, placeId: String)
    case lightStop(lightId: String)
    case choice(promptLineId: String, correct: Turn)
    /// "Spot it!" — the voice names something and the child taps the matching
    /// option. The first explicit *learning* beat (colors / counting / shapes).
    /// No failure: a wrong tap is gently re-prompted, never punished.
    case find(promptLineId: String, options: [FindOption], correctId: String)
    case cutscene(id: String)
    case reward(stars: Int, stickerId: String?)

    public enum Turn: String, Codable, Equatable, Sendable { case left, right }

    // MARK: Codable (tagged by "type")
    private enum CodingKeys: String, CodingKey {
        case type, lineId, placeId, arriveLineId, passengerId, atStop
        case lightId, promptLineId, correct, id, stars, stickerId
        case options, correctId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "say":
            self = .say(lineId: try c.decode(String.self, forKey: .lineId))
        case "driveTo":
            self = .driveTo(
                placeId: try c.decode(String.self, forKey: .placeId),
                arriveLineId: try c.decodeIfPresent(String.self, forKey: .arriveLineId)
            )
        case "pickup":
            self = .pickup(
                passengerId: try c.decode(String.self, forKey: .passengerId),
                atStop: try c.decode(String.self, forKey: .atStop)
            )
        case "dropoff":
            self = .dropoff(
                passengerId: try c.decode(String.self, forKey: .passengerId),
                placeId: try c.decode(String.self, forKey: .placeId)
            )
        case "lightStop":
            self = .lightStop(lightId: try c.decode(String.self, forKey: .lightId))
        case "choice":
            self = .choice(
                promptLineId: try c.decode(String.self, forKey: .promptLineId),
                correct: try c.decode(Turn.self, forKey: .correct)
            )
        case "find":
            self = .find(
                promptLineId: try c.decode(String.self, forKey: .promptLineId),
                options: try c.decode([FindOption].self, forKey: .options),
                correctId: try c.decode(String.self, forKey: .correctId)
            )
        case "cutscene":
            self = .cutscene(id: try c.decode(String.self, forKey: .id))
        case "reward":
            self = .reward(
                stars: try c.decode(Int.self, forKey: .stars),
                stickerId: try c.decodeIfPresent(String.self, forKey: .stickerId)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown beat type \"\(type)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .say(lineId):
            try c.encode("say", forKey: .type)
            try c.encode(lineId, forKey: .lineId)
        case let .driveTo(placeId, arriveLineId):
            try c.encode("driveTo", forKey: .type)
            try c.encode(placeId, forKey: .placeId)
            try c.encodeIfPresent(arriveLineId, forKey: .arriveLineId)
        case let .pickup(passengerId, atStop):
            try c.encode("pickup", forKey: .type)
            try c.encode(passengerId, forKey: .passengerId)
            try c.encode(atStop, forKey: .atStop)
        case let .dropoff(passengerId, placeId):
            try c.encode("dropoff", forKey: .type)
            try c.encode(passengerId, forKey: .passengerId)
            try c.encode(placeId, forKey: .placeId)
        case let .lightStop(lightId):
            try c.encode("lightStop", forKey: .type)
            try c.encode(lightId, forKey: .lightId)
        case let .choice(promptLineId, correct):
            try c.encode("choice", forKey: .type)
            try c.encode(promptLineId, forKey: .promptLineId)
            try c.encode(correct, forKey: .correct)
        case let .find(promptLineId, options, correctId):
            try c.encode("find", forKey: .type)
            try c.encode(promptLineId, forKey: .promptLineId)
            try c.encode(options, forKey: .options)
            try c.encode(correctId, forKey: .correctId)
        case let .cutscene(id):
            try c.encode("cutscene", forKey: .type)
            try c.encode(id, forKey: .id)
        case let .reward(stars, stickerId):
            try c.encode("reward", forKey: .type)
            try c.encode(stars, forKey: .stars)
            try c.encodeIfPresent(stickerId, forKey: .stickerId)
        }
    }
}

/// A complete story episode, authored as data.
public struct Episode: Codable, Equatable, Sendable {
    public var id: String
    public var titleId: String
    public var neighborhood: String
    public var beats: [Beat]
}

/// Top-level content bundle decoded from the Content/ folder.
public struct GameContent: Sendable {
    public var strings: [String: [String: String]]
    public var places: [Place]
    public var passengers: [Passenger]
    public var vehicles: [Vehicle]
    public var lights: [Light]
    public var collectibles: [Collectible]
    public var episodes: [Episode]

    public init(
        strings: [String: [String: String]] = [:],
        places: [Place] = [],
        passengers: [Passenger] = [],
        vehicles: [Vehicle] = [],
        lights: [Light] = [],
        collectibles: [Collectible] = [],
        episodes: [Episode] = []
    ) {
        self.strings = strings
        self.places = places
        self.passengers = passengers
        self.vehicles = vehicles
        self.lights = lights
        self.collectibles = collectibles
        self.episodes = episodes
    }

    public var localizer: Localizer { Localizer(table: strings) }
}
