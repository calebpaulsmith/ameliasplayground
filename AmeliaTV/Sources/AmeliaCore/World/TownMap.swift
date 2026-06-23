import Foundation

/// Named positions in the 2D town, in the same world coordinates the SpriteKit
/// scene renders (matching `RoadNetwork.demoTown`). Authored here as data so the
/// Adventure logic (`EpisodeRunner`) and the renderer agree on *where* places are
/// — and so a headless test can play the whole ride without a GPU.
///
/// The 2D town's road layout still lives in the scene today; this captures just
/// the handful of story-relevant stops the ride needs. Migrating the full town
/// layout into data is a later step (PLAN_2D Part 1 — "data-driven world").
public struct TownMap: Sendable, Equatable {
    /// place id → world position.
    public let places: [String: Vec2]

    public init(places: [String: Vec2]) { self.places = places }

    public func position(ofPlace id: String) -> Vec2? { places[id] }

    /// The M3 demo town: a bus stop on the top road, the school on the bottom
    /// road, and the garage on the left side — all sitting *on*
    /// `RoadNetwork.demoTown` so the bus reaches them just by driving the loop.
    public static let demo = TownMap(places: [
        "stopA": Vec2(-200, -700),   // Montrose (north road), west of centre
        "school": Vec2(-200, 700),   // Sunnyside (south road), by the school
        "garage": Vec2(-800, 0),     // Western (west road), middle
    ])
}

public extension Episode {
    /// M3 "first ride": pick up Pip at the bus stop, take her to the school,
    /// reward. This is the Adventure spine — drive → stop → pick up → drop off →
    /// reward — ported onto the 2D road network (PLAN_2D roadmap M3). Every line
    /// id resolves from `Content/strings` in both EN and ES.
    static var townFirstRide: Episode {
        Episode(
            id: "town-first-ride",
            titleId: "episode.firstDay.title",
            neighborhood: "town",
            beats: [
                .say(lineId: "m.goStop"),
                .driveTo(placeId: "stopA", arriveLineId: "m.pickup"),
                .pickup(passengerId: "pip", atStop: "stopA"),
                .say(lineId: "m.allAboard"),
                .driveTo(placeId: "school", arriveLineId: "m.dropSchool"),
                .dropoff(passengerId: "pip", placeId: "school"),
                .reward(stars: 3, stickerId: "first-day"),
            ]
        )
    }
}
