import AVFoundation
import Foundation

/// `talkatanormalvolumeflow --transcribe file.wav [--model small.en] [--raw]`
/// Prints the transcript and exits. Handy for testing the engine without a microphone.
enum DebugCLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--polish-test") { polishTest(); return true }
        if let i = args.firstIndex(of: "--mic-test") { micTest(seconds: i + 1 < args.count ? Double(args[i + 1]) ?? 3 : 3); return true }
        guard let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count else { return false }
        let file = URL(fileURLWithPath: args[i + 1])
        var modelId = Settings.shared.data.modelId
        if let m = args.firstIndex(of: "--model"), m + 1 < args.count { modelId = args[m + 1] }
        let raw = args.contains("--raw")

        var done = false
        Task {
            do {
                let samples = try load16k(file)
                let model = WhisperModel.byId(modelId)
                let path = ModelManager.shared.path(for: model).path
                let t0 = Date()
                try await WhisperEngine.shared.load(path: path)
                let t1 = Date()
                let settings = Settings.shared.data
                let text = try await WhisperEngine.shared.transcribe(samples: samples, language: settings.language,
                                                                     prompt: TextCleaner.whisperPrompt(from: settings))
                let t2 = Date()
                let cleaned = TextCleaner(settings: settings).clean(text)
                FileHandle.standardError.write("audio: \(String(format: "%.1f", Double(samples.count) / 16000))s  load: \(String(format: "%.2f", t1.timeIntervalSince(t0)))s  transcribe: \(String(format: "%.2f", t2.timeIntervalSince(t1)))s\n".data(using: .utf8)!)
                print(raw ? text : cleaned)
            } catch {
                FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
            }
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        WhisperEngine.shared.unloadSync()
        return true
    }

    /// `--mic-test [seconds]`: records from the default microphone, reports the level, and transcribes it.
    /// Tells apart "mic is muted / wrong device" from "recognition failed".
    static func micTest(seconds: Double) {
        let log: (String) -> Void = { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) }
        var done = false
        Task { @MainActor in
            log("microphone permission: \(Permissions.microphoneGranted ? "granted" : "NOT granted")")
            if let dev = AVCaptureDevice.default(for: .audio) { log("default input: \(dev.localizedName)") }
            let rec = AudioRecorder()
            do { try rec.start() } catch { log("start failed: \(error.localizedDescription)"); done = true; return }
            log("recording \(Int(seconds))s… say something")
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            let samples = rec.stop()
            let peak = samples.map { abs($0) }.max() ?? 0
            let rms = samples.isEmpty ? 0 : sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
            log(String(format: "captured %.1fs  peak %.4f  rms %.4f  %@", Double(samples.count) / 16000, peak, rms,
                       peak < 0.001 ? "→ SILENCE: mic is muted, wrong device selected, or permission denied" : "→ audio OK"))
            let settings = Settings.shared.data
            let model = WhisperModel.byId(settings.modelId)
            do {
                try await WhisperEngine.shared.load(path: ModelManager.shared.path(for: model).path)
                let raw = try await WhisperEngine.shared.transcribe(samples: samples, language: settings.language, prompt: TextCleaner.whisperPrompt(from: settings))
                log("raw transcript: \"\(raw)\"")
                log("cleaned: \"\(TextCleaner(settings: settings).clean(raw))\"")
            } catch { log("transcribe error: \(error.localizedDescription)") }
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        WhisperEngine.shared.unloadSync()
    }

    /// `--polish-test`: starts the bundled Ollama exactly like the Home screen button, downloads the model if needed,
    /// and polishes a sample sentence. Prints each stage.
    static func polishTest() {
        var done = false
        let log: (String) -> Void = { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) }
        Task {
            let o = OllamaManager.shared
            let model = Settings.shared.data.ollamaModel
            log("bundled binary: \(o.bundledBinary?.path ?? "NONE")")
            var t = Date()
            await o.ensureRunning()
            log("ensureRunning -> \(await MainActor.run { o.status }) in \(String(format: "%.1f", Date().timeIntervalSince(t)))s")
            guard o.isReady else { done = true; return }
            if !o.hasModel(model) {
                t = Date()
                log("pulling \(model)…")
                await o.pull(model: model)
                log("pull -> \(await MainActor.run { o.status }) in \(String(format: "%.0f", Date().timeIntervalSince(t)))s")
            }
            t = Date(); await o.warmUp(model: model); log("warmUp \(String(format: "%.1f", Date().timeIntervalSince(t)))s")
            let sample = "so um I was thinking we should move the meeting to Tuesday, no wait, Wednesday afternoon and and let the whole team know.\nAlso can you add John, sorry, Jen to the invite."
            t = Date()
            let out = await o.cleanup(sample, model: model, style: Settings.shared.data.ollamaStyle)
            log("cleanup \(String(format: "%.1f", Date().timeIntervalSince(t)))s")
            print("IN : \(sample.replacingOccurrences(of: "\n", with: " ⏎ "))")
            print("OUT: \(out?.replacingOccurrences(of: "\n", with: " ⏎ ") ?? "nil (fell back to rules)")")
            done = true
        }
        // Pump the main run loop so MainActor work can run while we wait.
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        OllamaManager.shared.stop()
    }

    static func load16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        guard let conv = AVAudioConverter(from: file.processingFormat, to: target) else { throw WhisperError.inferenceFailed }
        let ratio = 16000 / file.processingFormat.sampleRate
        let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 32)!
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if let err { throw err }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }
}
