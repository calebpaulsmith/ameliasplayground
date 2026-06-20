import Foundation

/// Something that can speak a resolved line aloud and show/clear a subtitle.
/// The app implements this with AVSpeechSynthesizer + a SwiftUI subtitle; tests
/// use a spy. This keeps the Core free of AVFoundation (docs/tvos/
/// TECHNICAL_ARCHITECTURE.md "Voice & dialogue system").
public protocol LineSpeaker: AnyObject {
    /// Speak `text` in `language`. Implementations should interrupt any line in
    /// progress (the game never talks over itself).
    func speak(_ text: String, language: Language)
    func stopSpeaking()
}

/// Resolves line ids to localized text and routes them to a `LineSpeaker`,
/// de-duping immediate repeats and exposing the current subtitle.
public final class DialogueDirector {
    private let localizer: Localizer
    public var language: Language
    private weak var speaker: LineSpeaker?

    public private(set) var currentSubtitle: String = ""
    private var lastSpokenText: String = ""

    public init(localizer: Localizer, language: Language, speaker: LineSpeaker? = nil) {
        self.localizer = localizer
        self.language = language
        self.speaker = speaker
    }

    /// Resolve `lineId` (+ vars) and speak it. Repeated identical text is ignored
    /// unless `force` is set. Returns the resolved text that was (or would be) spoken.
    @discardableResult
    public func play(_ lineId: String, vars: [String: String] = [:], force: Bool = false) -> String {
        let text = localizer.string(lineId, language, vars: vars)
        guard force || text != lastSpokenText else { return text }
        lastSpokenText = text
        currentSubtitle = text
        speaker?.speak(text, language: language)
        return text
    }

    public func clear() {
        currentSubtitle = ""
        lastSpokenText = ""
        speaker?.stopSpeaking()
    }
}
