import Foundation
import AVFoundation
import AmeliaCore

/// `LineSpeaker` backed by on-device text-to-speech (AVSpeechSynthesizer). This
/// is the v1 voice (docs/tvos/GAME_DESIGN.md §13/§14); recorded hero lines come
/// later, with this as the fallback. Bright, kid-friendly pitch.
final class SpeechSpeaker: LineSpeaker {
    private let synth = AVSpeechSynthesizer()

    /// When false, narration is silent — the game is designed to read from the
    /// graphics/HUD alone, so voice is an optional aid (Settings ▸ Voice).
    var isEnabled = true

    func speak(_ text: String, language: Language) {
        guard isEnabled else { return }
        synth.stopSpeaking(at: .immediate)   // never talk over ourselves
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language == .es ? "es-ES" : "en-US")
        utterance.pitchMultiplier = 1.25
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.98
        utterance.volume = 1
        synth.speak(utterance)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
    }
}
