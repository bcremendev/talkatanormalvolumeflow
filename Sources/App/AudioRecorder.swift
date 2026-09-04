import Foundation
import AVFoundation
import Combine

/// Records from the default input device and produces 16 kHz mono Float32 samples.
final class AudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0        // 0...1 smoothed RMS for the UI
    @Published private(set) var isRecording = false

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    func start() throws {
        guard !isRecording else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        guard let conv = AVAudioConverter(from: inFormat, to: targetFormat) else {
            throw NSError(domain: "audio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        converter = conv
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        DispatchQueue.main.async { self.isRecording = true }
    }

    /// Stops recording and returns the captured samples.
    func stop() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        lock.lock(); let out = samples; samples = []; lock.unlock()
        DispatchQueue.main.async { self.isRecording = false; self.level = 0 }
        return out
    }

    var durationSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(samples.count) / 16000
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData, out.frameLength > 0 else { return }
        let n = Int(out.frameLength)
        let ptr = UnsafeBufferPointer(start: ch[0], count: n)
        var sum: Float = 0
        for v in ptr { sum += v * v }
        let rms = sqrt(sum / Float(n))
        lock.lock(); samples.append(contentsOf: ptr); lock.unlock()
        let display = min(1, rms * 8)
        DispatchQueue.main.async { self.level = self.level * 0.6 + display * 0.4 }
    }
}
