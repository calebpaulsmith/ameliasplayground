import Foundation
import AVFoundation
import AmeliaCore

/// `SoundPlayer` backed by a procedural `AVAudioEngine` synth — the music & sound
/// pass for the 2D town.
///
/// The brief: a **mega-calming** ride through a tranquil neighborhood — think the
/// soft, spacious feel of *Minecraft*'s piano beds — over a world that genuinely
/// *sounds alive*: songbirds, a chittering squirrel, a bunny's foot-thump, bees
/// in the flowers, the hush of a passing car, and friendly stop/go cues at the
/// crossing. Everything is **synthesized** (no sample files): the bundle stays
/// tiny, there's no sample-licensing/originality question (D-IP-1), and real
/// recordings can be swapped in later behind the same `SoundCue`/`MusicTheme` ids.
///
/// Hard constraints (GAME_DESIGN.md §13): every sound is **gentle and never
/// startling**, mixed *below* the spoken voice (which lives on its own
/// `AVSpeechSynthesizer` channel), and the session uses `.mixWithOthers` so a
/// parent's own music keeps playing and we never duck harshly.
final class ProceduralAudio: SoundPlayer {

    private let engine = AVAudioEngine()
    private let sr: Double = 44_100
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    // Player nodes, one continuous layer each + a small one-shot pool so overlapping
    // cues (a chirp during a honk) don't cut each other off.
    private let sfxNodes: [AVAudioPlayerNode]
    private var nextSFX = 0
    private let musicNode = AVAudioPlayerNode()       // looping music bed
    private let ambienceNode = AVAudioPlayerNode()    // always-on nature bed (wind + birds)
    private let beeNode = AVAudioPlayerNode()         // bee buzz, loud only near flowers
    private let engineNode = AVAudioPlayerNode()      // bus engine hum, follows speed

    private var sfxBuffers: [SoundCue: AVAudioPCMBuffer] = [:]
    private var musicBuffers: [MusicTheme: AVAudioPCMBuffer] = [:]
    private var ambienceBuffer: AVAudioPCMBuffer?
    private var beeBuffer: AVAudioPCMBuffer?
    private var engineBuffer: AVAudioPCMBuffer?
    private var currentTheme: MusicTheme = .none
    private var started = false

    // Mix levels — the voice (separate channel) always sits on top of all of these.
    private let sfxVolume: Float = 0.5
    private let musicVolume: Float = 0.17
    private let ambienceVolume: Float = 0.13
    private let maxBeeVolume: Float = 0.09
    private let maxEngineVolume: Float = 0.085

    init() {
        sfxNodes = (0..<8).map { _ in AVAudioPlayerNode() }
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
        node.volume = sfxVolume * cueGain(cue)
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
        beeNode.volume = 0
        engineNode.volume = 0
    }

    // MARK: - Continuous, per-frame signals (not discrete cues)

    /// Turn the always-on nature ambience (soft wind + distant birdsong) on/off.
    func setAmbience(_ on: Bool) {
        guard started, let buf = ambienceBuffer else { return }
        if on {
            if !ambienceNode.isPlaying {
                ambienceNode.volume = ambienceVolume
                ambienceNode.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
                ambienceNode.play()
            }
        } else {
            ambienceNode.stop()
        }
    }

    /// Engine hum loudness, `0` (idle, never silent) … `1` (full speed).
    func setEngineIntensity(_ x: Double) {
        guard started else { return }
        let v = Float(max(0, min(1, x)))
        engineNode.volume = maxEngineVolume * (0.22 + 0.78 * v)
    }

    /// Bee-buzz loudness, `0` (no bees nearby) … `1` (right in the flowerbed).
    func setBeeIntensity(_ x: Double) {
        guard started else { return }
        beeNode.volume = maxBeeVolume * Float(max(0, min(1, x)))
    }

    /// Slightly hotter mix for the quietest, most intimate cues so they still read.
    private func cueGain(_ cue: SoundCue) -> Float {
        switch cue {
        case .rabbitThump, .lightCountdown, .squirrelChitter: return 0.85
        case .birdChirp, .birdSong, .beeBuzz: return 0.8
        default: return 1
        }
    }

    // MARK: - Engine setup

    private func configureSession() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    private func buildGraph() {
        let mixer = engine.mainMixerNode
        for node in sfxNodes { engine.attach(node); engine.connect(node, to: mixer, format: format) }
        for node in [musicNode, ambienceNode, beeNode, engineNode] {
            engine.attach(node); engine.connect(node, to: mixer, format: format)
        }
        mixer.outputVolume = 1
    }

    private func start() {
        engine.prepare()
        do {
            try engine.start()
            started = true
        } catch {
            // Audio is non-essential; on failure the game plays in silence.
            started = false
            return
        }
        if let bee = beeBuffer {
            beeNode.volume = 0
            beeNode.scheduleBuffer(bee, at: nil, options: [.loops], completionHandler: nil)
            beeNode.play()
        }
        if let hum = engineBuffer {
            engineNode.volume = maxEngineVolume * 0.22
            engineNode.scheduleBuffer(hum, at: nil, options: [.loops], completionHandler: nil)
            engineNode.play()
        }
    }

    private func prerender() {
        for cue in SoundCue.allCases { sfxBuffers[cue] = renderSFX(cue) }
        for theme in MusicTheme.allCases where theme != .none { musicBuffers[theme] = renderMusic(theme) }
        ambienceBuffer = buffer(from: renderAmbience())
        beeBuffer = buffer(from: renderBeeBuzz())
        engineBuffer = buffer(from: renderEngineHum())
    }

    // MARK: - Low-level synthesis helpers

    /// A soft bell/marimba-ish note: a fundamental plus a couple of quiet partials,
    /// a quick attack and a long, gentle decay. The voice of the calm melody.
    private func addBell(_ out: inout [Float], freq: Double, start: Double, dur: Double, amp: Double) {
        let s0 = Int(start * sr), len = max(1, Int(dur * sr))
        let attack = max(1, Int(0.012 * sr))
        let partials: [(Double, Double)] = [(1, 1.0), (2.01, 0.28), (3.0, 0.1)]   // slight inharmonicity
        for k in 0..<len {
            let i = s0 + k
            if i < 0 || i >= out.count { continue }
            let env: Double
            if k < attack { env = Double(k) / Double(attack) }
            else { env = pow(1 - Double(k - attack) / Double(max(1, len - attack)), 2.2) }
            let t = Double(k) / sr
            var s = 0.0
            for (mult, a) in partials { s += a * sin(2 * .pi * freq * mult * t) }
            out[i] += Float(amp * env * s)
        }
    }

    /// A pitch-gliding whistle (used for birdsong). Phase is accumulated so the
    /// frequency can sweep smoothly without clicks.
    private func addGlide(_ out: inout [Float], from f0: Double, to f1: Double,
                          start: Double, dur: Double, amp: Double) {
        let s0 = Int(start * sr), len = max(1, Int(dur * sr))
        let attack = max(1, Int(0.01 * sr)), release = max(1, Int(0.02 * sr))
        var phase = 0.0
        for k in 0..<len {
            let i = s0 + k
            let p = Double(k) / Double(len)
            let f = f0 + (f1 - f0) * p
            phase += f / sr
            if i < 0 || i >= out.count { continue }
            var env = 1.0
            if k < attack { env = Double(k) / Double(attack) }
            else if k > len - release { env = Double(len - k) / Double(release) }
            out[i] += Float(amp * env * sin(2 * .pi * phase))
        }
    }

    /// Fold any decay tail that runs past the loop point back over the start, so a
    /// buffer with notes/reverb near the seam loops click-free. `tail` extra
    /// samples are rendered then wrapped into the head.
    private func wrapTail(_ arr: inout [Float], length n: Int, tail: Int) {
        for i in 0..<min(tail, n) { arr[i] += arr[n + i] }
        arr.removeLast(arr.count - n)
    }

    /// Cheap multi-tap reverb: a few attenuated delayed copies give the melody air
    /// without a real reverb unit. Operates in place on a dry buffer.
    private func addReverb(_ buf: inout [Float]) {
        let dry = buf
        let taps: [(Double, Float)] = [(0.11, 0.5), (0.23, 0.34), (0.37, 0.22), (0.55, 0.13)]
        for (delay, gain) in taps {
            let d = Int(delay * sr)
            if d <= 0 || d >= dry.count { continue }
            for i in d..<dry.count { buf[i] += dry[i - d] * gain }
        }
    }

    private func softClip(_ arr: inout [Float], drive: Float = 1.0) {
        for i in 0..<arr.count { arr[i] = tanhf(arr[i] * drive) }
    }

    // MARK: - Music beds

    private func renderMusic(_ theme: MusicTheme) -> AVAudioPCMBuffer {
        switch theme {
        case .driving: return buffer(from: renderCalmBed())
        case .garage:  return buffer(from: renderPadBed(chord: [130.81, 196.0, 261.63, 329.63],
                                                        melody: [392.0, 329.63, 261.63], duration: 8, slow: true))
        case .reward:  return buffer(from: renderPadBed(chord: [261.63, 329.63, 392.0, 523.25],
                                                        melody: [523.25, 659.25, 784.0, 1046.5], duration: 4, slow: false))
        case .none:    return buffer(from: [Float](repeating: 0, count: 1))
        }
    }

    /// The hero "driving" bed: a soft, sustained low pad under a slow, sparse
    /// C-major-pentatonic bell melody with reverb — open, unhurried, mega-calming.
    private func renderCalmBed() -> [Float] {
        let duration = 16.0
        let n = Int(duration * sr)
        let fundamental = 1.0 / duration

        // --- warm low pad (snapped to whole cycles so it loops seamlessly) ---
        var pad = [Float](repeating: 0, count: n)
        let drone: [(Double, Double)] = [(65.41, 0.5), (98.0, 0.34), (130.81, 0.3), (196.0, 0.2)] // C2 G2 C3 G3
        for (f, a) in drone {
            let snapped = (f / fundamental).rounded() * fundamental
            for i in 0..<n {
                let t = Double(i) / sr
                pad[i] += Float(a * sin(2 * .pi * snapped * t))
            }
        }
        for i in 0..<n {                                   // very slow breath (2 whole cycles)
            let t = Double(i) / sr
            let breath = 0.78 + 0.22 * sin(2 * .pi * 2 * t / duration)
            pad[i] = Float(Double(pad[i]) * 0.16 * breath)
        }

        // --- sparse pentatonic melody with reverb (folded so the tail loops) ---
        let tail = Int(2.5 * sr)
        var mel = [Float](repeating: 0, count: n + tail)
        // C-major pentatonic: C E G A C E (D added for colour). Gentle, falling phrases.
        let line: [(Double, Double)] = [
            (0.0, 523.25), (1.5, 659.25), (3.2, 440.0), (4.8, 392.0),
            (6.6, 587.33), (8.2, 523.25), (10.0, 392.0), (11.6, 440.0),
            (13.2, 329.63), (14.8, 392.0),
        ]
        for (start, freq) in line {
            addBell(&mel, freq: freq, start: start, dur: 2.0, amp: 0.5)
            addBell(&mel, freq: freq * 2, start: start, dur: 1.3, amp: 0.08)   // faint shimmer octave
        }
        addReverb(&mel)
        wrapTail(&mel, length: n, tail: tail)

        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = pad[i] + mel[i] * 0.42 }
        softClip(&out, drive: 0.95)
        return out
    }

    /// A simpler pad-plus-occasional-note bed for the garage / reward screens.
    private func renderPadBed(chord: [Double], melody: [Double], duration: Double, slow: Bool) -> [Float] {
        let n = Int(duration * sr)
        let fundamental = 1.0 / duration
        var pad = [Float](repeating: 0, count: n)
        let amp = 1.0 / Double(max(1, chord.count))
        for f in chord {
            let snapped = (f / fundamental).rounded() * fundamental
            for i in 0..<n {
                let t = Double(i) / sr
                pad[i] += Float(amp * sin(2 * .pi * snapped * t))
            }
        }
        for i in 0..<n {
            let t = Double(i) / sr
            let trem = 0.82 + 0.18 * sin(2 * .pi * (slow ? 1.0 : 2.0) * t / duration)
            pad[i] = Float(Double(pad[i]) * 0.7 * trem)
        }
        let tail = Int(1.5 * sr)
        var mel = [Float](repeating: 0, count: n + tail)
        let step = duration / Double(melody.count + 1)
        for (k, f) in melody.enumerated() {
            addBell(&mel, freq: f, start: step * Double(k + 1), dur: slow ? 1.6 : 0.9, amp: 0.4)
        }
        addReverb(&mel)
        wrapTail(&mel, length: n, tail: tail)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = pad[i] + mel[i] * 0.5 }
        softClip(&out, drive: 0.95)
        return out
    }

    // MARK: - Continuous ambience / bee / engine loops

    /// The always-on nature bed: a soft filtered-noise breeze with a slow swell,
    /// plus a few faint background birdsongs baked in so the air is never dead.
    private func renderAmbience() -> [Float] {
        let duration = 9.0
        let n = Int(duration * sr)
        let fade = Int(0.6 * sr)
        var arr = [Float](repeating: 0, count: n + fade)
        // gentle wind: white noise → one-pole low-pass, swelling slowly
        var lp: Float = 0
        let a: Float = 0.012                                  // low cutoff → soft "shhh"
        for i in 0..<arr.count {
            let white = Float.random(in: -1...1)
            lp += a * (white - lp)
            let t = Double(i) / sr
            let swell = 0.5 + 0.5 * sin(2 * .pi * t / duration)   // one swell per loop
            arr[i] = lp * Float(0.5 + 0.5 * swell)
        }
        // a softer, lower murmur layer (distant park)
        var lp2: Float = 0
        for i in 0..<arr.count {
            let white = Float.random(in: -1...1)
            lp2 += 0.004 * (white - lp2)
            arr[i] += lp2 * 0.6
        }
        // faint background birdsong, spread across the loop (away from the seam)
        addGlide(&arr, from: 2400, to: 3100, start: 1.2, dur: 0.10, amp: 0.05)
        addGlide(&arr, from: 3100, to: 2700, start: 1.34, dur: 0.10, amp: 0.05)
        addGlide(&arr, from: 1900, to: 2500, start: 4.5, dur: 0.12, amp: 0.045)
        addGlide(&arr, from: 2800, to: 2800, start: 6.8, dur: 0.08, amp: 0.04)
        addGlide(&arr, from: 2600, to: 3200, start: 6.95, dur: 0.10, amp: 0.04)
        // crossfade the tail back into the head for a click-free loop
        for i in 0..<fade {
            let w = Float(i) / Float(fade)
            arr[i] = arr[i] * w + arr[n + i] * (1 - w)
        }
        arr.removeLast(arr.count - n)
        softClip(&arr, drive: 1.0)
        return arr
    }

    /// A soft, warm bee buzz: a few harmonics of a low fundamental with a gentle
    /// wing-beat tremolo. Snapped to whole cycles over the loop so it's seamless.
    private func renderBeeBuzz() -> [Float] {
        let duration = 1.5
        let n = Int(duration * sr)
        let fundamental = 1.0 / duration
        var arr = [Float](repeating: 0, count: n)
        let f0 = (172.0 / fundamental).rounded() * fundamental
        for h in 1...6 {
            let a = 0.5 / Double(h)
            for i in 0..<n {
                let t = Double(i) / sr
                arr[i] += Float(a * sin(2 * .pi * f0 * Double(h) * t))
            }
        }
        let beats = (28.0 / fundamental).rounded() * fundamental    // ~28Hz wing tremolo
        for i in 0..<n {
            let t = Double(i) / sr
            let trem = 0.6 + 0.4 * sin(2 * .pi * beats * t)
            arr[i] = Float(Double(arr[i]) * 0.22 * trem)
        }
        softClip(&arr, drive: 1.1)
        return arr
    }

    /// A low, warm, seamless engine hum.
    private func renderEngineHum() -> [Float] {
        let duration = 1.0
        let n = Int(duration * sr)
        let fundamental = 1.0 / duration
        var arr = [Float](repeating: 0, count: n)
        for (f, a) in [(70.0, 0.5), (140.0, 0.34), (210.0, 0.12)] {
            let snapped = (f / fundamental).rounded() * fundamental
            for i in 0..<n {
                let t = Double(i) / sr
                arr[i] += Float(a * sin(2 * .pi * snapped * t))
            }
        }
        softClip(&arr, drive: 1.0)
        return arr
    }

    // MARK: - One-shot effects

    private func renderSFX(_ cue: SoundCue) -> AVAudioPCMBuffer {
        switch cue {
        case .horn:
            return buffer(from: tones(total: 0.40, [(392, 0, 0.40, 0.5), (523, 0, 0.40, 0.4)]))
        case .doorOpen:
            return buffer(from: tones(total: 0.36, [(523, 0, 0.16, 0.5), (698, 0.16, 0.20, 0.5)]))
        case .doorClose:
            return buffer(from: tones(total: 0.36, [(698, 0, 0.16, 0.5), (523, 0.16, 0.20, 0.5)]))
        case .starSparkle:
            return buffer(from: tones(total: 0.42, [(1047, 0, 0.14, 0.4), (1319, 0.10, 0.14, 0.4), (1568, 0.20, 0.22, 0.4)]))
        case .chime:
            return buffer(from: tones(total: 0.55, [(784, 0, 0.55, 0.45), (988, 0, 0.55, 0.3)]))
        case .bump:
            return buffer(from: tones(total: 0.22, [(140, 0, 0.22, 0.5), (90, 0, 0.22, 0.4)]))
        case .reward:
            return buffer(from: tones(total: 1.0, [(523, 0, 0.22, 0.45), (659, 0.18, 0.22, 0.45),
                                                   (784, 0.36, 0.22, 0.45), (1047, 0.54, 0.42, 0.5)]))
        case .rewardSticker:
            return buffer(from: tones(total: 0.6, [(1319, 0, 0.16, 0.35), (1760, 0.14, 0.16, 0.35), (2093, 0.28, 0.30, 0.3)]))

        case .birdChirp:
            // two quick rising tweets
            var a = [Float](repeating: 0, count: Int(0.34 * sr))
            addGlide(&a, from: 2200, to: 3000, start: 0.0, dur: 0.08, amp: 0.45)
            addGlide(&a, from: 2400, to: 3200, start: 0.14, dur: 0.09, amp: 0.45)
            softClip(&a); return buffer(from: a)
        case .birdSong:
            // a three-note descending whistle (cuckoo-ish)
            var a = [Float](repeating: 0, count: Int(0.5 * sr))
            addGlide(&a, from: 2600, to: 2700, start: 0.0, dur: 0.10, amp: 0.4)
            addGlide(&a, from: 2100, to: 2150, start: 0.16, dur: 0.10, amp: 0.4)
            addGlide(&a, from: 1700, to: 1500, start: 0.32, dur: 0.14, amp: 0.4)
            softClip(&a); return buffer(from: a)
        case .squirrelChitter:
            // a fast burst of tiny high blips
            var a = [Float](repeating: 0, count: Int(0.36 * sr))
            var t = 0.0
            for k in 0..<7 {
                let f = 1800.0 + Double((k % 3)) * 420.0
                addGlide(&a, from: f, to: f + 200, start: t, dur: 0.022, amp: 0.32)
                t += 0.045
            }
            softClip(&a); return buffer(from: a)
        case .rabbitThump:
            // two soft, low foot-thumps
            var a = [Float](repeating: 0, count: Int(0.3 * sr))
            addBell(&a, freq: 115, start: 0.0, dur: 0.09, amp: 0.6)
            addBell(&a, freq: 105, start: 0.13, dur: 0.10, amp: 0.5)
            softClip(&a, drive: 1.2); return buffer(from: a)
        case .beeBuzz:
            // a single bee passing: the buzz tone, faded in and out
            var a = [Float](repeating: 0, count: Int(0.5 * sr))
            let n = a.count
            for h in 1...5 {
                let amp = 0.4 / Double(h)
                for i in 0..<n {
                    let t = Double(i) / sr
                    let trem = 0.6 + 0.4 * sin(2 * .pi * 26 * t)
                    a[i] += Float(amp * trem * sin(2 * .pi * 175 * Double(h) * t))
                }
            }
            let edge = Int(0.08 * sr)
            for i in 0..<n {                                   // raised-cosine in/out
                let env: Float
                if i < edge { env = Float(i) / Float(edge) }
                else if i > n - edge { env = Float(n - i) / Float(edge) }
                else { env = 1 }
                a[i] *= env * 0.5
            }
            softClip(&a); return buffer(from: a)
        case .crossingWait:
            // gentle, calm two "boop"s — wait, please (never the harsh real beep)
            return buffer(from: tones(total: 0.7, [(620, 0.0, 0.18, 0.45), (620, 0.32, 0.18, 0.45)]))
        case .crossingWalk:
            // friendly rising "you can go" chirp
            var a = [Float](repeating: 0, count: Int(0.5 * sr))
            addGlide(&a, from: 700, to: 1050, start: 0.0, dur: 0.18, amp: 0.45)
            addGlide(&a, from: 1050, to: 1050, start: 0.22, dur: 0.16, amp: 0.4)
            softClip(&a); return buffer(from: a)
        case .lightCountdown:
            // one soft tick
            return buffer(from: tones(total: 0.12, [(784, 0, 0.09, 0.4)]))
        case .lightGo:
            // bright, happy two-note go!
            return buffer(from: tones(total: 0.5, [(523, 0, 0.16, 0.45), (659, 0.16, 0.30, 0.5)]))
        case .carPass:
            return renderCarPass()
        }
    }

    /// Sum of soft plucked sine notes (`freq, start, dur, amp`) with a quick attack
    /// and gentle decay, then soft-clipped. The friendly C-major SFX palette.
    private func tones(total: Double, _ notes: [(Double, Double, Double, Double)]) -> [Float] {
        let n = max(1, Int(total * sr))
        var out = [Float](repeating: 0, count: n)
        let attack = max(1, Int(0.008 * sr))
        for (freq, start, dur, amp) in notes {
            let s0 = Int(start * sr), len = max(1, Int(dur * sr))
            for k in 0..<len {
                let i = s0 + k
                if i >= n { break }
                let env: Double
                if k < attack { env = Double(k) / Double(attack) }
                else { env = pow(1 - Double(k - attack) / Double(max(1, len - attack)), 1.6) }
                let t = Double(k) / sr
                out[i] += Float(amp * env * sin(2 * .pi * freq * t))
            }
        }
        for i in 0..<n { out[i] = tanhf(out[i] * 1.2) }
        return out
    }

    /// A soft car whoosh: low-passed noise swelling under a raised-cosine envelope,
    /// panned left→right so the car seems to roll past.
    private func renderCarPass() -> AVAudioPCMBuffer {
        let dur = 0.8
        let n = Int(dur * sr)
        var mono = [Float](repeating: 0, count: n)
        var lp: Float = 0
        for i in 0..<n {
            let white = Float.random(in: -1...1)
            lp += 0.05 * (white - lp)
            mono[i] = lp
        }
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        guard let L = buf.floatChannelData?[0], let R = buf.floatChannelData?[1] else { return buf }
        for i in 0..<n {
            let p = Double(i) / Double(n)
            let env = Float(sin(.pi * p))           // swell in and out
            let s = mono[i] * env * 0.5
            L[i] = s * Float(1 - p)                  // starts on the left…
            R[i] = s * Float(p)                      // …ends on the right
        }
        return buf
    }

    /// Wrap a mono sample array into a stereo PCM buffer (both channels identical).
    private func buffer(from samples: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        for ch in 0..<Int(format.channelCount) {
            if let dst = buf.floatChannelData?[ch] {
                samples.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: samples.count)
                }
            }
        }
        return buf
    }
}
