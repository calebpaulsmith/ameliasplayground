import Foundation
import AVFoundation
import AmeliaCore

/// `SoundPlayer` backed by a small procedural `AVAudioEngine` synth (A2-13).
///
/// We deliberately **synthesize** every effect and music bed rather than ship
/// audio files: the slice is "TTS + synthesized SFX" (docs/tvos/VERTICAL_SLICE.md),
/// which keeps the bundle tiny, sidesteps any sample-licensing / originality
/// questions (D-IP-1), and lets real recorded audio be swapped in later behind the
/// same `SoundCue` / `MusicTheme` ids. Everything here is intentionally **gentle
/// and non-frantic**, mixed below the spoken voice (which uses its own channel via
/// `SpeechSpeaker`), per the child-first audio constraints (GAME_DESIGN.md §13).
final class ProceduralAudio: SoundPlayer {

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    /// Round-robin pool so overlapping one-shots don't cut each other off.
    private let sfxNodes: [AVAudioPlayerNode]
    private var nextSFX = 0
    private let musicNode = AVAudioPlayerNode()
    private let engineNode = AVAudioPlayerNode()   // continuous bus hum

    private var sfxBuffers: [SoundCue: AVAudioPCMBuffer] = [:]
    private var musicBuffers: [MusicTheme: AVAudioPCMBuffer] = [:]
    private var engineBuffer: AVAudioPCMBuffer?
    private var currentTheme: MusicTheme = .none
    private var started = false

    // Mix levels — voice (separate AVSpeech channel) always sits on top.
    private let sfxVolume: Float = 0.55
    private let musicVolume: Float = 0.16
    private let maxEngineVolume: Float = 0.10

    init() {
        sfxNodes = (0..<6).map { _ in AVAudioPlayerNode() }
        configureSession()
        buildGraph()
        prerender()
        start()
    }

    // MARK: - SoundPlayer

    func play(_ cue: SoundCue) {
        guard started, let buffer = sfxBuffers[cue] else { return }
        let node = sfxNodes[nextSFX]
        nextSFX = (nextSFX + 1) % sfxNodes.count
        node.stop()
        node.volume = sfxVolume
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        node.play()
    }

    func setMusic(_ theme: MusicTheme) {
        guard started, theme != currentTheme else { return }
        currentTheme = theme
        musicNode.stop()
        guard theme != .none, let buffer = musicBuffers[theme] else { return }
        musicNode.volume = musicVolume
        musicNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        musicNode.play()
    }

    func stopAll() {
        currentTheme = .none
        musicNode.stop()
        sfxNodes.forEach { $0.stop() }
        engineNode.volume = 0
    }

    /// Continuous engine hum whose loudness follows how fast the bus is moving.
    /// Called from the render loop (not part of the `SoundPlayer` protocol, since
    /// it's a per-frame signal rather than a discrete cue).
    func setEngineIntensity(_ x: Double) {
        guard started else { return }
        let v = Float(max(0, min(1, x)))
        // Idle never fully silent; ramps up gently with speed.
        engineNode.volume = maxEngineVolume * (0.25 + 0.75 * v)
    }

    // MARK: - Engine setup

    private func configureSession() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        // Play our soft bed but let any background audio (e.g. a parent's music)
        // keep going; never duck harshly.
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    private func buildGraph() {
        for node in sfxNodes { engine.attach(node) }
        engine.attach(musicNode)
        engine.attach(engineNode)
        for node in sfxNodes { engine.connect(node, to: engine.mainMixerNode, format: format) }
        engine.connect(musicNode, to: engine.mainMixerNode, format: format)
        engine.connect(engineNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
    }

    private func start() {
        engine.prepare()
        do {
            try engine.start()
            started = true
        } catch {
            // Audio is non-essential; if the engine won't start, the game still
            // plays in silence rather than crashing.
            started = false
            return
        }
        // Kick off the always-on (initially near-silent) engine hum.
        if let hum = engineBuffer {
            engineNode.volume = maxEngineVolume * 0.25
            engineNode.scheduleBuffer(hum, at: nil, options: [.loops], completionHandler: nil)
            engineNode.play()
        }
    }

    // MARK: - Synthesis

    private func prerender() {
        for cue in SoundCue.allCases { sfxBuffers[cue] = renderSFX(cue) }
        for theme in MusicTheme.allCases where theme != .none {
            musicBuffers[theme] = renderMusic(theme)
        }
        engineBuffer = renderEngineHum()
    }

    /// A single voiced note inside a one-shot effect.
    private struct Note { var freq: Double; var start: Double; var dur: Double; var amp: Double }

    private func renderSFX(_ cue: SoundCue) -> AVAudioPCMBuffer {
        // C-major-ish friendly pitches; nothing harsh or dissonant.
        let notes: [Note]
        let total: Double
        switch cue {
        case .horn:
            // Warm two-tone toot.
            total = 0.40
            notes = [Note(freq: 392, start: 0, dur: 0.40, amp: 0.5),
                     Note(freq: 523, start: 0, dur: 0.40, amp: 0.4)]
        case .doorOpen:
            // Two gentle ascending notes.
            total = 0.36
            notes = [Note(freq: 523, start: 0.0, dur: 0.16, amp: 0.5),
                     Note(freq: 698, start: 0.16, dur: 0.20, amp: 0.5)]
        case .doorClose:
            // Two gentle descending notes.
            total = 0.36
            notes = [Note(freq: 698, start: 0.0, dur: 0.16, amp: 0.5),
                     Note(freq: 523, start: 0.16, dur: 0.20, amp: 0.5)]
        case .starSparkle:
            // Quick bright rising triad.
            total = 0.42
            notes = [Note(freq: 1047, start: 0.00, dur: 0.14, amp: 0.4),
                     Note(freq: 1319, start: 0.10, dur: 0.14, amp: 0.4),
                     Note(freq: 1568, start: 0.20, dur: 0.22, amp: 0.4)]
        case .chime:
            // Soft bell, a happy major third.
            total = 0.55
            notes = [Note(freq: 784, start: 0, dur: 0.55, amp: 0.45),
                     Note(freq: 988, start: 0, dur: 0.55, amp: 0.30)]
        case .bump:
            // Low, soft, quick — a friendly "nope, this way" nudge, never alarming.
            total = 0.22
            notes = [Note(freq: 140, start: 0, dur: 0.22, amp: 0.5),
                     Note(freq: 90, start: 0, dur: 0.22, amp: 0.4)]
        case .reward:
            // Little ascending fanfare (C-E-G-C).
            total = 1.0
            notes = [Note(freq: 523, start: 0.00, dur: 0.22, amp: 0.45),
                     Note(freq: 659, start: 0.18, dur: 0.22, amp: 0.45),
                     Note(freq: 784, start: 0.36, dur: 0.22, amp: 0.45),
                     Note(freq: 1047, start: 0.54, dur: 0.42, amp: 0.5)]
        case .rewardSticker:
            // An extra high sparkle on top of the fanfare.
            total = 0.6
            notes = [Note(freq: 1319, start: 0.00, dur: 0.16, amp: 0.35),
                     Note(freq: 1760, start: 0.14, dur: 0.16, amp: 0.35),
                     Note(freq: 2093, start: 0.28, dur: 0.30, amp: 0.30)]
        }
        return buffer(from: renderNotes(notes, total: total))
    }

    /// Sums plucked sine notes with a quick attack and gentle decay, then soft-clips.
    private func renderNotes(_ notes: [Note], total: Double) -> [Float] {
        let sr = format.sampleRate
        let n = max(1, Int(total * sr))
        var out = [Float](repeating: 0, count: n)
        let attack = max(1, Int(0.008 * sr))
        for note in notes {
            let s0 = Int(note.start * sr)
            let len = max(1, Int(note.dur * sr))
            for k in 0..<len {
                let i = s0 + k
                if i >= n { break }
                let env: Double
                if k < attack {
                    env = Double(k) / Double(attack)
                } else {
                    let p = Double(k - attack) / Double(max(1, len - attack))
                    env = pow(1 - p, 1.6)                       // gentle pluck decay
                }
                let t = Double(k) / sr
                out[i] += Float(note.amp * env * sin(2 * .pi * note.freq * t))
            }
        }
        // Soft-clip so overlapping notes stay smooth, never clipped/harsh.
        for i in 0..<n { out[i] = tanhf(out[i] * 1.2) }
        return out
    }

    /// A short seamless music loop: a soft chord pad with a slow tremolo. Each
    /// partial is snapped to a whole number of cycles over the loop so the buffer
    /// loops click-free, and the tremolo uses whole cycles for the same reason.
    private func renderMusic(_ theme: MusicTheme) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let chord: [Double]
        let duration: Double
        let tremoloCycles: Double
        switch theme {
        case .garage:
            // Warm, cozy C major.
            chord = [130.81, 196.0, 261.63, 329.63]
            duration = 4.0
            tremoloCycles = 2
        case .driving:
            // Rolling, slightly brighter G-rooted bed.
            chord = [146.83, 220.0, 293.66, 392.0]
            duration = 4.0
            tremoloCycles = 4
        case .reward:
            // Bright, sustained celebratory C major.
            chord = [261.63, 329.63, 392.0, 523.25]
            duration = 3.0
            tremoloCycles = 1
        case .none:
            chord = []
            duration = 1.0
            tremoloCycles = 1
        }
        let n = max(1, Int(duration * sr))
        var out = [Float](repeating: 0, count: n)
        let fundamental = 1.0 / duration
        let amp = 1.0 / Double(max(1, chord.count))
        for f in chord {
            // Snap to a whole number of cycles across the loop → seamless.
            let snapped = (f / fundamental).rounded() * fundamental
            for i in 0..<n {
                let t = Double(i) / sr
                out[i] += Float(amp * sin(2 * .pi * snapped * t))
            }
        }
        // Slow tremolo (whole cycles, so the seam stays continuous).
        for i in 0..<n {
            let t = Double(i) / sr
            let trem = 0.82 + 0.18 * sin(2 * .pi * tremoloCycles * t / duration)
            out[i] = tanhf(out[i] * Float(0.9 * trem))
        }
        return buffer(from: out)
    }

    /// A low, seamless hum used as the continuously-looping bus engine.
    private func renderEngineHum() -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let duration = 1.0
        let n = max(1, Int(duration * sr))
        var out = [Float](repeating: 0, count: n)
        let fundamental = 1.0 / duration
        for f in [70.0, 140.0] {
            let snapped = (f / fundamental).rounded() * fundamental
            for i in 0..<n {
                let t = Double(i) / sr
                out[i] += Float(0.5 * sin(2 * .pi * snapped * t))
            }
        }
        for i in 0..<n { out[i] = tanhf(out[i]) }
        return buffer(from: out)
    }

    private func buffer(from samples: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            if let dst = buf.floatChannelData?[ch] {
                samples.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: samples.count)
                }
            }
        }
        return buf
    }
}
