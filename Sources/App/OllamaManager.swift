import Foundation
import Combine

/// Optional AI cleanup. Uses an already-running Ollama if present, otherwise starts the bundled one.
final class OllamaManager: ObservableObject {
    static let shared = OllamaManager()

    enum Status: Equatable { case off, starting, ready(String), pulling(Double, String), error(String) }

    @Published private(set) var status: Status = .off
    @Published private(set) var installedModels: [String] = []

    private var process: Process?
    private var baseURL = URL(string: "http://127.0.0.1:11434")!
    private let bundledPort = 11539
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 600
        return URLSession(configuration: c)
    }()

    static let suggestedModels = ["qwen2.5:3b", "qwen2.5:1.5b", "llama3.2:3b", "gemma3:1b"]

    var bundledBinary: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ollama/ollama"),
            Bundle.main.bundleURL.appendingPathComponent("../../vendor/ollama/ollama").standardizedFileURL,   // swift build dev runs
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isReady: Bool { if case .ready = status { return true } else { return false } }

    // MARK: lifecycle

    /// Ensures a server is reachable. Returns when ready (or sets .error).
    func ensureRunning() async {
        if isReady, await ping(baseURL) { return }
        await MainActor.run { status = .starting }

        // 1. External Ollama (Homebrew / Ollama.app) already running?
        let external = URL(string: "http://127.0.0.1:11434")!
        if await ping(external) {
            baseURL = external
            await refreshModels()
            await MainActor.run { status = .ready("system Ollama") }
            return
        }

        // 2. Bundled server we started earlier?
        let bundled = URL(string: "http://127.0.0.1:\(bundledPort)")!
        if await ping(bundled) {
            baseURL = bundled
            await refreshModels()
            await MainActor.run { status = .ready("bundled Ollama") }
            return
        }

        // 3. Start the bundled server.
        guard let bin = bundledBinary else {
            await MainActor.run { status = .error("Ollama is not bundled in this build and not installed. Install from ollama.com or rebuild with vendor/ollama present.") }
            return
        }
        let p = Process()
        p.executableURL = bin
        p.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "127.0.0.1:\(bundledPort)"
        env["OLLAMA_MODELS"] = AppPaths.ollama.appendingPathComponent("models").path
        env["OLLAMA_KEEP_ALIVE"] = "30m"
        env["OLLAMA_NUM_PARALLEL"] = "1"
        env["OLLAMA_MAX_LOADED_MODELS"] = "1"
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil
                if case .ready = self.status { self.status = .off }
            }
        }
        do {
            try p.run()
        } catch {
            await MainActor.run { status = .error("Could not start bundled Ollama: \(error.localizedDescription)") }
            return
        }
        process = p
        baseURL = bundled
        for _ in 0..<160 {   // up to 40 s: first GPU discovery can take ~20 s
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await ping(bundled) {
                await refreshModels()
                await MainActor.run { status = .ready("bundled Ollama") }
                return
            }
            if !p.isRunning { break }
        }
        await MainActor.run { status = .error("Bundled Ollama did not start.") }
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        DispatchQueue.main.async { self.status = .off }
    }

    private func ping(_ url: URL) async -> Bool {
        var req = URLRequest(url: url.appendingPathComponent("api/version"))
        req.timeoutInterval = 1.5
        guard let (_, resp) = try? await session.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: models

    func refreshModels() async {
        struct Tags: Decodable { struct M: Decodable { let name: String }; let models: [M] }
        guard let (data, _) = try? await session.data(from: baseURL.appendingPathComponent("api/tags")),
              let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return }
        let names = tags.models.map(\.name)
        await MainActor.run {
            installedModels = names
            let want = Settings.shared.data.ollamaModel
            if names.contains(want) || names.contains(want + ":latest") { Settings.shared.data.polishReady = true }
        }
    }

    /// Loads the model into memory so the first dictation isn't slow.
    func warmUp(model: String) async {
        guard isReady, hasModel(model) else { return }
        let body: [String: Any] = ["model": model, "keep_alive": "30m", "messages": [], "stream": false]
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }

    /// Starts the server (if polish is on and downloaded) and preloads the model.
    func prepareIfActive() async {
        let s = Settings.shared.data
        guard s.polishActive else { return }
        await ensureRunning()
        await warmUp(model: s.ollamaModel)
    }

    func hasModel(_ name: String) -> Bool {
        let want = name.contains(":") ? name : name + ":latest"
        return installedModels.contains(want) || installedModels.contains(name)
    }

    /// Streams `ollama pull` progress into `status`.
    func pull(model: String) async {
        await ensureRunning()
        guard isReady else { return }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": model, "stream": true])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await MainActor.run { status = .pulling(0, model) }
        do {
            let (bytes, _) = try await session.bytes(for: req)
            for try await line in bytes.lines {
                guard let d = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if let err = obj["error"] as? String {
                    await MainActor.run { status = .error("Pull failed: \(err)") }
                    return
                }
                let total = (obj["total"] as? Double) ?? 0
                let done = (obj["completed"] as? Double) ?? 0
                let frac = total > 0 ? done / total : 0
                let st = (obj["status"] as? String) ?? ""
                await MainActor.run { status = .pulling(frac, st.isEmpty ? model : st) }
            }
            await refreshModels()
            await MainActor.run { status = .ready(baseURL.port == bundledPort ? "bundled Ollama" : "system Ollama") }
        } catch {
            await MainActor.run { status = .error("Pull failed: \(error.localizedDescription)") }
        }
    }

    // MARK: cleanup

    static let systemPrompt = """
    You clean up speech-to-text transcripts. Return the same message as clean written text.
    Rules:
    - Keep the speaker's exact words, tone, and casual voice. Do NOT paraphrase, formalize, summarize, expand, answer, or add anything.
    - Fix punctuation, capitalization, and obvious mis-heard words. Remove filler words (um, uh, like, you know) and stutters/repeats.
    - Apply spoken self-corrections. "Tuesday, no wait, Wednesday" becomes "Wednesday". "add John, sorry, Jen" becomes "add Jen". "at 3, I mean 4" becomes "at 4".
    - Keep line breaks that are already in the text.
    - No markdown, no quotes, no preamble. Output ONLY the cleaned text.
    Example input: "okay so um the client said they they want the deep clean done before friday, no, thursday. let me know if that works"
    Example output: "Okay, so the client said they want the deep clean done before Thursday. Let me know if that works."
    Example input: "can you add John, sorry, Jen to the invite and uh send it by 3, I mean 4"
    Example output: "Can you add Jen to the invite and send it by 4?"
    Example input: "yeah no that's totally fine just ping me when you're done"
    Example output: "Yeah, no, that's totally fine. Just ping me when you're done."
    """

    /// Cleans each line separately so line/paragraph breaks from voice commands are always preserved.
    /// Returns nil if any segment fails (caller falls back to rule-based text).
    func cleanup(_ text: String, model: String, style: String) async -> String? {
        guard isReady else { return nil }
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { out.append(""); continue }
            guard let cleaned = await cleanupSegment(trimmed, model: model, style: style) else { return nil }
            out.append(cleaned)
        }
        return out.joined(separator: "\n")
    }

    private func cleanupSegment(_ text: String, model: String, style: String, timeout: TimeInterval = 25) async -> String? {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": "30m",
            "options": ["temperature": 0.1, "num_predict": 1024],
            "messages": [
                ["role": "system", "content": Self.systemPrompt + "\nStyle guidance: " + style],
                ["role": "user", "content": "Transcript:\n\(text)"],
            ],
        ]
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              var out = msg["content"] as? String else { return nil }

        // Strip <think> blocks and wrapping quotes some models add.
        out = out.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("\""), out.hasSuffix("\""), out.count > 2 { out = String(out.dropFirst().dropLast()) }
        for prefix in ["Cleaned text:", "Here is the cleaned text:", "Here's the cleaned text:", "Transcript:"] {
            if out.lowercased().hasPrefix(prefix.lowercased()) { out = String(out.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        // Sanity check: reject wild rewrites.
        let ratio = Double(out.count) / Double(max(1, text.count))
        guard !out.isEmpty, ratio > 0.35, ratio < 1.8 else { return nil }
        return out
    }
}
