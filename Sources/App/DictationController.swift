import AppKit
import Combine

@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum State: Equatable {
        case idle
        case recording
        case processing(String)
        case notice(String)     // transient message shown in the overlay
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var modelStatus: String = "Model not loaded"
    /// Set by the Home page while its "Try it" box is visible. Returns true if it took the text.
    var localInsertHandler: ((String) -> Bool)?

    let recorder = AudioRecorder()
    let hotkeys = HotkeyManager()
    private let overlay = OverlayController()
    private var cancellables = Set<AnyCancellable>()
    private var pressStarted: Date?
    private var targetApp: NSRunningApplication?
    private var noticeTask: Task<Void, Never>?

    private var settings: SettingsData { Settings.shared.data }

    private init() {
        hotkeys.onPress = { [weak self] in self?.handlePress() }
        hotkeys.onRelease = { [weak self] in self?.handleRelease() }
        hotkeys.onEscape = { [weak self] in
            guard let self, self.state == .recording else { return false }
            self.cancel()
            return true
        }
        Settings.shared.$data
            .map(\.shortcut).removeDuplicates()
            .sink { [weak self] s in self?.hotkeys.shortcut = s }
            .store(in: &cancellables)
        Settings.shared.$data
            .map(\.modelId).removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.preloadModel() }
            .store(in: &cancellables)
        overlay.bind(controller: self)
    }

    var isRecording: Bool { state == .recording }

    // MARK: setup

    func startHotkeys() -> Bool { hotkeys.start() }

    func preloadModel() {
        let model = WhisperModel.byId(settings.modelId)
        guard ModelManager.shared.isDownloaded(model) else {
            modelStatus = "Speech recognizer not downloaded yet"
            return
        }
        modelStatus = "Getting ready…"
        Task.detached(priority: .userInitiated) {
            do {
                try await WhisperEngine.shared.load(path: ModelManager.shared.path(for: model).path)
                await MainActor.run { self.modelStatus = "Ready · \(model.tier.title) accuracy" }
            } catch {
                await MainActor.run { self.modelStatus = error.localizedDescription }
            }
        }
    }

    // MARK: hotkey handling

    func handlePress() {
        switch settings.mode {
        case .hold:
            pressStarted = Date()
            if state == .idle || isNotice { begin() }
        case .toggle:
            if state == .recording { finish() } else if state == .idle || isNotice { begin() }
        }
    }

    func handleRelease() {
        guard settings.mode == .hold, state == .recording else { return }
        if let s = pressStarted, Date().timeIntervalSince(s) < 0.25 {
            cancel()   // accidental tap
        } else {
            finish()
        }
    }

    /// Menu-bar entry point: start or stop regardless of mode.
    func toggleFromMenu() {
        if state == .recording { finish() } else if state == .idle || isNotice { begin() }
    }

    private var isNotice: Bool { if case .notice = state { return true } else { return false } }

    // MARK: flow

    private func begin() {
        noticeTask?.cancel()
        guard Permissions.microphoneGranted else {
            showNotice("Microphone access needed — see Settings → Permissions", seconds: 3)
            Task { _ = await Permissions.requestMicrophone() }
            return
        }
        let model = WhisperModel.byId(settings.modelId)
        guard ModelManager.shared.isDownloaded(model) else {
            showNotice("Download the speech model first (see the app window)", seconds: 3)
            AppDelegate.shared?.showMain(page: .transcription)
            return
        }
        if !WhisperEngine.shared.isLoaded { preloadModel() }
        targetApp = NSWorkspace.shared.frontmostApplication
        do {
            try recorder.start()
        } catch {
            showNotice("Mic error: \(error.localizedDescription)", seconds: 3)
            return
        }
        state = .recording
        if settings.playSounds { Sounds.start() }
        if settings.showOverlay { overlay.show() }
    }

    private func cancel() {
        _ = recorder.stop()
        state = .idle
        overlay.hide()
        if settings.playSounds { Sounds.cancel() }
    }

    private func finish() {
        let samples = recorder.stop()
        let duration = Double(samples.count) / 16000
        if settings.playSounds { Sounds.stop() }
        guard duration > 0.3 else { state = .idle; overlay.hide(); return }
        // Dead silence means the mic is muted, the wrong device is selected, or macOS is blocking audio
        // (that can happen right after the app is updated). Say so instead of a vague "Didn't catch that".
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if peak < 0.002 {
            showNotice("No sound reached the app. Is the mic muted? Check System Settings → Sound → Input, and Privacy & Security → Microphone.", seconds: 6)
            return
        }
        state = .processing("Transcribing…")
        let snapshot = settings
        let app = targetApp
        Task { await process(samples: samples, duration: duration, settings: snapshot, app: app) }
    }

    private func process(samples: [Float], duration: Double, settings: SettingsData, app: NSRunningApplication?) async {
        do {
            let model = WhisperModel.byId(settings.modelId)
            try await WhisperEngine.shared.load(path: ModelManager.shared.path(for: model).path)
            let prompt = TextCleaner.whisperPrompt(from: settings)
            let raw = try await WhisperEngine.shared.transcribe(samples: samples, language: settings.language, prompt: prompt)
            var text = TextCleaner(settings: settings).clean(raw)

            if text.isEmpty {
                showNotice("Didn't catch that", seconds: 1.5)
                return
            }

            if settings.polishActive {
                state = .processing("Polishing…")
                let ollama = OllamaManager.shared
                await ollama.ensureRunning()
                if ollama.isReady, let polished = await ollama.cleanup(text, model: settings.ollamaModel, style: settings.ollamaStyle) {
                    text = polished
                }
            }

            var toInsert = text
            if settings.trailingSpace, !toInsert.hasSuffix("\n") { toInsert += " " }

            state = .processing("Inserting…")
            // Dictating into our own window (the "Try it" box): hand the text over directly, no paste needed.
            let isSelf = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            if isSelf, let handler = localInsertHandler, handler(toInsert) {
                // handled
            } else {
                // Make sure the original app is frontmost before pasting.
                if let app, app != NSWorkspace.shared.frontmostApplication { app.activate() ; try? await Task.sleep(nanoseconds: 120_000_000) }
                TextInserter.insert(toInsert, method: settings.insertMethod, restoreClipboard: settings.restoreClipboard)
            }

            if settings.historyEnabled {
                HistoryStore.shared.add(HistoryEntry(date: Date(), text: text, rawText: raw,
                                                     appName: app?.localizedName ?? "", durationSeconds: duration))
            }
            state = .idle
            overlay.hide()
        } catch {
            lastError = error.localizedDescription
            showNotice(error.localizedDescription, seconds: 3)
        }
    }

    private func showNotice(_ message: String, seconds: Double) {
        state = .notice(message)
        if settings.showOverlay { overlay.show() }
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isNotice else { return }
            self.state = .idle
            self.overlay.hide()
        }
    }
}
