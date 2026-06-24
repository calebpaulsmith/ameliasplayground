import Foundation

/// One-shot sound effects used by the vertical slice (A2-13).
///
/// These are referenced by **id**, never by file: the app's audio engine
/// synthesizes each one procedurally (the slice ships "TTS + synthesized SFX" —
/// docs/tvos/VERTICAL_SLICE.md), so gameplay never waits on audio assets and real
/// recorded samples can be swapped in later behind the same ids without touching
/// game code (the same id-with-placeholder rule we use for 3D models).
///
/// Tone is a hard constraint: every cue must be **calm and non-frantic**, and the
/// spoken voice always mixes *above* effects (docs/tvos/GAME_DESIGN.md §13).
public enum SoundCue: String, CaseIterable, Sendable {
    /// Friendly little toot as the bus sets off.
    case horn
    /// A passenger climbs aboard.
    case doorOpen
    /// A passenger settles in / steps off at their stop.
    case doorClose
    /// A single star is earned (pairs with `EpisodeEvent.starSparkle`).
    case starSparkle
    /// A light turns green or a sign/destination is reached — a soft, happy chime.
    case chime
    /// A gentle bump used as *soft, non-punishing* feedback (e.g. "let's try the
    /// other way" at a fork). Never alarming.
    case bump
    /// The completion flourish on the reward screen.
    case reward
    /// An extra sparkle when a brand-new sticker is granted.
    case rewardSticker

    // MARK: - Music & sound pass (a living, calm neighborhood)
    //
    // The town should *sound* alive: songbirds, a chittering squirrel, a soft
    // bunny foot-thump, bees around the flowers, the hush of a passing car, plus
    // the friendly stop/go cues at the crossing. Like everything above, these are
    // referenced by id and synthesized procedurally — gentle, never startling.

    /// A short, sweet two-note songbird tweet.
    case birdChirp
    /// A second, brighter little warble, so the birdsong never sounds like one bird.
    case birdSong
    /// A quick, friendly squirrel chitter.
    case squirrelChitter
    /// A soft, low bunny foot-thump on the grass.
    case rabbitThump
    /// A brief, cozy bee buzz (a bee passing close by a flower).
    case beeBuzz
    /// The pedestrian-crossing "wait" signal — gentle, never the harsh real beep:
    /// people are crossing, so the bus should wait.
    case crossingWait
    /// The crossing "you can go now" signal — a friendly little rising chirp.
    case crossingWalk
    /// One soft tick of the traffic-light countdown (3… 2… 1…).
    case lightCountdown
    /// The light turns green — a bright, happy "go!" two-note.
    case lightGo
    /// A soft whoosh as another car rolls past.
    case carPass
}

/// Looping background music beds. Exactly one plays at a time; the audio engine
/// crossfades between them. Kept gentle so the voice always sits on top.
public enum MusicTheme: String, CaseIterable, Sendable {
    /// Silence (e.g. menus / before anything starts).
    case none
    /// Warm, cozy home-base theme for the garage (A2-07).
    case garage
    /// Rolling, unhurried loop while driving the route.
    case driving
    /// Brief celebratory bed under the reward / completion screen (A2-12).
    case reward
}
