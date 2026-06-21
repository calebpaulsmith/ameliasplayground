import Foundation

/// Plays sound effects and background music for the game.
///
/// Mirrors `LineSpeaker`: the app implements this with a procedural
/// `AVAudioEngine`, while tests use a spy. Keeping it a protocol leaves the Core
/// free of AVFoundation so a full playthrough is unit-testable headlessly
/// (docs/tvos/TECHNICAL_ARCHITECTURE.md).
///
/// Implementations must keep effects and music gentle, and must **never** play
/// over the spoken voice at a louder level — the voice (`LineSpeaker`) is always
/// the priority channel.
public protocol SoundPlayer: AnyObject {
    /// Trigger a one-shot effect. Cheap and fire-and-forget; overlapping cues are
    /// fine. Should never block gameplay or throw — audio is non-essential.
    func play(_ cue: SoundCue)

    /// Switch the looping music bed (crossfading from whatever is playing).
    /// Setting `.none` fades music out.
    func setMusic(_ theme: MusicTheme)

    /// Stop all music and effects (e.g. when leaving a scene).
    func stopAll()
}
