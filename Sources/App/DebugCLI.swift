import AVFoundation
import Foundation

/// `talkatanormalvolumeflow --transcribe file.wav [--model small.en] [--raw]`
/// Prints the transcript and exits. Handy for testing the engine without a microphone.
enum DebugCLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count else { return false }
        let file = URL(fileURLWithPath: args[i + 1])
        var modelId = Settings.shared.data.modelId
        if let m = args.firstIndex(of: "--model"), m + 1 < args.count { modelId = args[m + 1] }
        let raw = args.contains("--raw")

        let sem = DispatchSemaphore(value: 0)
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
            sem.signal()
        }
        sem.wait()
        WhisperEngine.shared.unloadSync()
        return true
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
