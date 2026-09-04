import AppKit
import AVFoundation

/// Ten short, pleasant tone sets for "listening started" / "listening stopped". Each is synthesized in code
/// (no audio files to ship): the start sound rises, the stop sound falls, cancel is a low blip.
struct SoundTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    fileprivate let start: Tone
    fileprivate let stop: Tone
    fileprivate let cancel: Tone

    static let all: [SoundTheme] = [
        SoundTheme(id: "chime", name: "Chime", blurb: "Two gentle bells",
                   start: Tone(notes: [523.25, 659.25], partials: [1, 0.35], decay: 0.35),
                   stop: Tone(notes: [659.25, 523.25], partials: [1, 0.35], decay: 0.35),
                   cancel: Tone(notes: [330], partials: [1, 0.35], decay: 0.25)),
        SoundTheme(id: "marimba", name: "Marimba", blurb: "Warm and woody",
                   start: Tone(notes: [440, 554.37], partials: [1, 0.05, 0, 0.25], decay: 0.18, gap: 0.08),
                   stop: Tone(notes: [554.37, 440], partials: [1, 0.05, 0, 0.25], decay: 0.18, gap: 0.08),
                   cancel: Tone(notes: [293.66], partials: [1, 0.05, 0, 0.25], decay: 0.18)),
        SoundTheme(id: "bell", name: "Bell", blurb: "A single clear ring",
                   start: Tone(notes: [880], partials: [1, 0.5, 0.3, 0.15], ratios: [1, 2.0, 2.98, 4.2], decay: 0.6),
                   stop: Tone(notes: [659.25], partials: [1, 0.5, 0.3, 0.15], ratios: [1, 2.0, 2.98, 4.2], decay: 0.6),
                   cancel: Tone(notes: [440], partials: [1, 0.5, 0.3], ratios: [1, 2.0, 2.98], decay: 0.35)),
        SoundTheme(id: "glass", name: "Glass", blurb: "Bright and delicate",
                   start: Tone(notes: [1318.5, 1568], partials: [1, 0.2], decay: 0.4, gap: 0.07, shimmer: 3),
                   stop: Tone(notes: [1568, 1318.5], partials: [1, 0.2], decay: 0.4, gap: 0.07, shimmer: 3),
                   cancel: Tone(notes: [784], partials: [1, 0.2], decay: 0.3, shimmer: 3)),
        SoundTheme(id: "bubble", name: "Bubble", blurb: "A quick pop",
                   start: Tone(notes: [420], sweepTo: 840, partials: [1], decay: 0.16, attack: 0.005),
                   stop: Tone(notes: [840], sweepTo: 420, partials: [1], decay: 0.16, attack: 0.005),
                   cancel: Tone(notes: [400], sweepTo: 250, partials: [1], decay: 0.16, attack: 0.005)),
        SoundTheme(id: "pluck", name: "Pluck", blurb: "A guitar string",
                   start: Tone(notes: [329.63, 493.88], partials: [1, 0.5, 0.33, 0.25, 0.2, 0.16], decay: 0.25, gap: 0.09),
                   stop: Tone(notes: [493.88, 329.63], partials: [1, 0.5, 0.33, 0.25, 0.2, 0.16], decay: 0.25, gap: 0.09),
                   cancel: Tone(notes: [220], partials: [1, 0.5, 0.33, 0.25], decay: 0.22)),
        SoundTheme(id: "dingdong", name: "Ding-dong", blurb: "A tiny doorbell",
                   start: Tone(notes: [523.25, 783.99], partials: [1, 0.3, 0.1], decay: 0.4, gap: 0.14),
                   stop: Tone(notes: [783.99, 523.25], partials: [1, 0.3, 0.1], decay: 0.4, gap: 0.14),
                   cancel: Tone(notes: [392], partials: [1, 0.3, 0.1], decay: 0.3)),
        SoundTheme(id: "harp", name: "Harp", blurb: "A three-note ripple",
                   start: Tone(notes: [523.25, 659.25, 783.99], partials: [1, 0.4, 0.2], decay: 0.5, gap: 0.06),
                   stop: Tone(notes: [783.99, 659.25, 523.25], partials: [1, 0.4, 0.2], decay: 0.5, gap: 0.06),
                   cancel: Tone(notes: [392, 329.63], partials: [1, 0.4, 0.2], decay: 0.3, gap: 0.06)),
        SoundTheme(id: "soft", name: "Soft", blurb: "One quiet note",
                   start: Tone(notes: [660], partials: [1], decay: 0.3, attack: 0.03),
                   stop: Tone(notes: [520], partials: [1], decay: 0.3, attack: 0.03),
                   cancel: Tone(notes: [330], partials: [1], decay: 0.25, attack: 0.03)),
        SoundTheme(id: "tap", name: "Tap", blurb: "Two crisp taps",
                   start: Tone(notes: [800, 1000], partials: [1, 0.3], decay: 0.06, gap: 0.07),
                   stop: Tone(notes: [1000, 800], partials: [1, 0.3], decay: 0.06, gap: 0.07),
                   cancel: Tone(notes: [500], partials: [1, 0.3], decay: 0.06)),
    ]
    static func byId(_ id: String) -> SoundTheme { all.first { $0.id == id } ?? all[0] }
}

/// Description of a short synthesized sound: one or more notes played in quick succession.
fileprivate struct Tone: Hashable {
    var notes: [Double]                 // fundamental frequencies, played `gap` seconds apart
    var sweepTo: Double? = nil          // if set, each note glides to this frequency over its decay
    var partials: [Double]              // relative amplitude of each harmonic (or of each `ratios` entry)
    var ratios: [Double]? = nil         // partial frequency ratios; defaults to 1, 2, 3…
    var decay: Double                   // seconds to fade to near-silence
    var gap: Double = 0.1
    var attack: Double = 0.004
    var shimmer: Double = 0             // slight detune (Hz) for a glassy wobble

    func render(sampleRate: Double = 44100) -> [Float] {
        let length = Int(sampleRate * (Double(max(0, notes.count - 1)) * gap + decay * 3 + 0.05))
        var out = [Float](repeating: 0, count: length)
        for (i, f0) in notes.enumerated() {
            let onset = Int(sampleRate * gap * Double(i))
            let n = min(Int(sampleRate * decay * 3), length - onset)
            var phases = [Double](repeating: 0, count: partials.count)
            for k in 0..<n {
                let t = Double(k) / sampleRate
                let env = min(1, t / attack) * exp(-t / (decay / 2.5))
                let f = sweepTo.map { f0 + ($0 - f0) * min(1, t / decay) } ?? f0
                var v = 0.0
                for (p, amp) in partials.enumerated() where amp > 0 {
                    let ratio = ratios?[p] ?? Double(p + 1)
                    phases[p] += 2 * .pi * (f * ratio + (p % 2 == 1 ? shimmer : 0)) / sampleRate
                    v += amp * sin(phases[p])
                }
                out[onset + k] += Float(v * env)
            }
        }
        let peak = out.map { abs($0) }.max() ?? 1
        if peak > 0 { for k in 0..<out.count { out[k] = out[k] / peak * 0.45 } }
        return out
    }
}

/// Plays the current theme's sounds. Rendered once per theme and cached as NSSound.
@MainActor
enum Sounds {
    private static var cache: [String: NSSound] = [:]

    static func start() { play(.start) }
    static func stop() { play(.stop) }
    static func cancel() { play(.cancel) }

    enum Kind { case start, stop, cancel }

    static func play(_ kind: Kind, theme id: String? = nil) {
        let theme = SoundTheme.byId(id ?? Settings.shared.data.soundTheme)
        let tone: Tone
        switch kind { case .start: tone = theme.start; case .stop: tone = theme.stop; case .cancel: tone = theme.cancel }
        let key = "\(theme.id)-\(kind)"
        if cache[key] == nil { cache[key] = NSSound(data: wav(tone.render())) }
        cache[key]?.stop()
        cache[key]?.play()
    }

    /// Start, then stop, so the user can hear how a theme feels.
    static func preview(theme id: String) {
        play(.start, theme: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { play(.stop, theme: id) }
    }

    private static func wav(_ samples: [Float], sampleRate: Int = 44100) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            pcm.append(UInt8(truncatingIfNeeded: v)); pcm.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
