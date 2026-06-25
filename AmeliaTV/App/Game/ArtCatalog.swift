import Foundation

/// Central registry of 2D art asset ids. Every sprite the town renders is named
/// here in ONE place — the "reference art by id, with a placeholder fallback"
/// guarantee from the architecture rules. To swap final art, drop a PNG into
/// `Assets/Kenney/` with the same name (or repoint an id here); a missing texture
/// falls back to a visible placeholder in `TownScene.kenneySprite`, so gameplay
/// never waits on art.
///
/// Today these resolve to **Kenney CC0** sprites (Racing Pack — see
/// `Assets/Kenney/KENNEY-LICENSE.txt`). The hero bus and the oblique buildings
/// stay hand-drawn on purpose (original IP, D-IP-1).
enum ArtCatalog {
    /// Full-size top-down cars, one variant per colour — used for parked traffic
    /// and the oncoming car. Order is fixed so CI captures stay deterministic.
    static let cars = ["car_blue_1", "car_red_1", "car_green_1", "car_black_1", "car_yellow_1"]

    /// Compact cars, for size variety in a parked row.
    static let smallCars = ["car_blue_small_1", "car_red_small_1", "car_black_small_1"]

    /// A parked motorcycle, an occasional change of pace in the row.
    static let motorcycle = "motorcycle_black"

    /// Roadside tree sprite.
    static let treeLarge = "tree_large"

    /// Townsfolk (passengers, park life, sidewalk pedestrians).
    static let people = ["character_brown_blue", "character_blonde_red",
                         "character_black_green", "character_blonde_white",
                         "character_brown_red"]
}
