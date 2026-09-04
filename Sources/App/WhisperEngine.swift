import Foundation
import whisper

enum WhisperError: LocalizedError {
    case noModel, loadFailed(String), inferenceFailed
    var errorDescription: String? {
        switch self {
        case .noModel: return "No speech model is downloaded yet. Open Settings → Transcription."
        case .loadFailed(let p): return "Could not load model at \(p)"
        case .inferenceFailed: return "Transcription failed"
        }
    }
}

/// Thin wrapper around whisper.cpp. All work happens on a private serial queue.
final class WhisperEngine {
    static let shared = WhisperEngine()

    private var ctx: OpaquePointer?
    private(set) var loadedPath: String?
    private let queue = DispatchQueue(label: "talkatanormalvolumeflow.whisper", qos: .userInitiated)

    private init() {
        // Silence whisper/ggml logging.
        whisper_log_set({ _, _, _ in }, nil)
        ggml_log_set({ _, _, _ in }, nil)
    }

    var isLoaded: Bool { ctx != nil }

    /// Loads the model at `path` if not already loaded.
    func load(path: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                if self.loadedPath == path, self.ctx != nil { cont.resume(); return }
                if let old = self.ctx { whisper_free(old); self.ctx = nil; self.loadedPath = nil }
                var cparams = whisper_context_default_params()
                cparams.use_gpu = true
                cparams.flash_attn = true
                guard let c = whisper_init_from_file_with_params(path, cparams) else {
                    cont.resume(throwing: WhisperError.loadFailed(path)); return
                }
                self.ctx = c
                self.loadedPath = path
                cont.resume()
            }
        }
    }

    /// Frees the model synchronously. Call before process exit to avoid ggml teardown asserts.
    func unloadSync() {
        queue.sync {
            if let c = self.ctx { whisper_free(c) }
            self.ctx = nil
            self.loadedPath = nil
        }
    }

    func unload() {
        queue.async {
            if let c = self.ctx { whisper_free(c) }
            self.ctx = nil
            self.loadedPath = nil
        }
    }

    /// Transcribes 16 kHz mono float samples.
    func transcribe(samples: [Float], language: String, prompt: String?) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                guard let ctx = self.ctx else { cont.resume(throwing: WhisperError.noModel); return }

                // whisper needs at least ~1s of audio; pad with silence and add a tail.
                var audio = samples
                let minSamples = 16000 * 11 / 10
                if audio.count < minSamples { audio.append(contentsOf: [Float](repeating: 0, count: minSamples - audio.count)) }
                audio.append(contentsOf: [Float](repeating: 0, count: 8000))

                var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
                params.beam_search.beam_size = 5
                params.greedy.best_of = 5
                params.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount)))
                params.translate = false
                params.no_context = true
                params.no_timestamps = true
                params.single_segment = false
                params.print_special = false
                params.print_progress = false
                params.print_realtime = false
                params.print_timestamps = false
                params.suppress_blank = true
                params.suppress_nst = true
                params.temperature_inc = 0.2
                params.entropy_thold = 2.4
                params.logprob_thold = -1.0
                params.no_speech_thold = 0.6

                let isMultilingual = whisper_is_multilingual(ctx) != 0
                let lang = isMultilingual ? language : "en"
                let langC = strdup(lang == "auto" ? "auto" : lang)
                let promptC = prompt.map { strdup($0) }
                defer { free(langC); if let promptC { free(promptC) } }
                params.language = UnsafePointer(langC)
                params.detect_language = false
                if let promptC { params.initial_prompt = UnsafePointer(promptC) }

                let rc = audio.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
                guard rc == 0 else { cont.resume(throwing: WhisperError.inferenceFailed); return }

                var text = ""
                let n = whisper_full_n_segments(ctx)
                for i in 0..<n {
                    if let s = whisper_full_get_segment_text(ctx, i) { text += String(cString: s) }
                }
                cont.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
