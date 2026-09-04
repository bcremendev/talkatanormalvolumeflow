import SwiftUI
import ServiceManagement

enum LaunchAtLogin {
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Launch at login failed: \(error)") }
    }
}

/// Shared card look for every settings page.
struct Card<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content() }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

// MARK: - Shortcut & Behavior

struct GeneralTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false

    var body: some View {
        PageScroll {
            Card(title: "Your shortcut", subtitle: "The key you hold (or press) to dictate. It works in every app.") {
                HStack(spacing: 10) {
                    ForEach(Shortcut.presets, id: \.self) { p in
                        Button {
                            settings.data.shortcut = p
                        } label: {
                            Text(p.displayName).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.data.shortcut == p ? .accentColor : nil)
                        .controlSize(.large)
                    }
                }
                HStack {
                    Text("Current:").foregroundStyle(.secondary)
                    Text(settings.data.shortcut.displayName).fontWeight(.semibold)
                    Spacer()
                    Button(recording ? "Press any key now…" : "Use a different key…") { record() }.disabled(recording)
                }
                if settings.data.shortcut.keyCode == 63 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Stop the emoji picker from popping up: in System Settings → Keyboard, set **“Press 🌐 key to”** to **Do Nothing**.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }.controlSize(.small)
                        }
                    }
                }
            }
            Card(title: "How the key works") {
                Picker("", selection: $settings.data.mode) {
                    ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            Card(title: "Behavior") {
                Toggle("Open automatically when I log in", isOn: launchAtLogin)
                Toggle("Play a soft sound when listening starts and stops", isOn: $settings.data.playSounds)
                Toggle("Add a space after each dictation (so you can keep talking)", isOn: $settings.data.trailingSpace)
            }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { settings.data.launchAtLogin }, set: { on in
            settings.data.launchAtLogin = on
            LaunchAtLogin.set(on)
        })
    }

    private func record() {
        recording = true
        DictationController.shared.hotkeys.recorder = { keyCode, flags, isModifier in
            DispatchQueue.main.async {
                recording = false
                if isModifier {
                    if let preset = Shortcut.presets.first(where: { $0.keyCode == keyCode }) {
                        settings.data.shortcut = preset
                    } else if Shortcut.flag(forModifierKeyCode: keyCode) != nil {
                        settings.data.shortcut = Shortcut(keyCode: keyCode, modifiers: 0, isModifierKey: true,
                                                          name: KeyNames.name(for: keyCode))
                    }
                } else {
                    if keyCode == 53 { return } // Escape cancels
                    settings.data.shortcut = Shortcut(keyCode: keyCode, modifiers: flags.rawValue, isModifierKey: false,
                                                      name: Shortcut.describe(keyCode: keyCode, flags: flags))
                }
            }
        }
    }
}

// MARK: - Speech Model

struct TranscriptionTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var controller = DictationController.shared

    var body: some View {
        PageScroll {
            Card(title: "Speech recognition", subtitle: "Runs entirely on this Mac. Your voice never leaves your computer. “Small (English)” is the right choice for almost everyone.") {
                LabeledContent("Status", value: controller.modelStatus)
            }
            Card(title: "Models") {
                ForEach(WhisperModel.all) { m in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(m.name).fontWeight(settings.data.modelId == m.id ? .semibold : .regular)
                                if settings.data.modelId == m.id {
                                    Text("IN USE").font(.caption2).bold().padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                                }
                            }
                            Text("\(m.sizeMB) MB · \(m.note)").font(.caption).foregroundStyle(.secondary)
                            if let e = models.errors[m.id] { Text(e).font(.caption).foregroundStyle(.red) }
                        }
                        Spacer()
                        if let p = models.progress[m.id] {
                            ProgressView(value: p).frame(width: 90)
                            Text("\(Int(p * 100))%").font(.caption).monospacedDigit().frame(width: 36)
                            Button("Cancel") { models.cancel(m) }.controlSize(.small)
                        } else if models.isDownloaded(m) {
                            if settings.data.modelId != m.id {
                                Button("Use") { settings.data.modelId = m.id }.controlSize(.small)
                                Button(role: .destructive) { models.delete(m) } label: { Image(systemName: "trash") }.controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        } else {
                            Button("Download") { models.download(m) }.controlSize(.small)
                        }
                    }
                    if m.id != WhisperModel.all.last?.id { Divider() }
                }
            }
            if !WhisperModel.byId(settings.data.modelId).englishOnly {
                Card(title: "Spoken language") {
                    Picker("", selection: $settings.data.language) {
                        Text("Auto-detect").tag("auto")
                        ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    static let languages: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt", "Portuguese"), ("it", "Italian"),
        ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("tr", "Turkish"), ("ar", "Arabic"),
        ("hi", "Hindi"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("vi", "Vietnamese"), ("tl", "Tagalog"),
        ("sv", "Swedish"), ("da", "Danish"), ("no", "Norwegian"), ("fi", "Finnish"),
    ]
}

// MARK: - Cleanup & AI Polish

struct CleanupTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var ollama = OllamaManager.shared
    @State private var newFrom = ""
    @State private var newTo = ""

    var body: some View {
        PageScroll {
            Card(title: "AI polish", subtitle: PolishCopy.why) {
                Toggle("Polish my dictations with AI", isOn: polishToggle)
                    .toggleStyle(.switch)
                if settings.data.ollamaEnabled && !settings.data.polishSkipped {
                    PolishStatusRow()
                    Picker("Model", selection: $settings.data.ollamaModel) {
                        ForEach(OllamaManager.suggestedModels, id: \.self) { Text(PolishCopy.label(for: $0)).tag($0) }
                    }
                    .onChange(of: settings.data.ollamaModel) { _, _ in
                        settings.data.polishReady = ollama.hasModel(settings.data.ollamaModel)
                    }
                }
            }
            Card(title: "Always-on cleanup", subtitle: "Instant fixes that run on every dictation, even without AI polish.") {
                Toggle("Remove filler words (um, uh, hmm…)", isOn: $settings.data.removeFillers)
                Toggle("Voice commands: “new line”, “new paragraph”, “scratch that”", isOn: $settings.data.voiceCommands)
            }
            Card(title: "Words it gets wrong", subtitle: "Teach it names and terms. “Heard as” → “Should be”. These also help recognition.") {
                ForEach(settings.data.replacements) { r in
                    HStack {
                        Text(r.from).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(r.to).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
                        Button { settings.data.replacements.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Heard as (e.g. zen made)", text: $newFrom)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Should be (e.g. ZenMaid)", text: $newTo)
                    Button("Add") {
                        settings.data.replacements.append(Replacement(from: newFrom.trimmingCharacters(in: .whitespaces), to: newTo.trimmingCharacters(in: .whitespaces)))
                        newFrom = ""; newTo = ""
                    }
                    .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty || newTo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .task { await ollama.prepareIfActive() }
    }

    private var polishToggle: Binding<Bool> {
        Binding(get: { settings.data.ollamaEnabled && !settings.data.polishSkipped }, set: { on in
            settings.data.ollamaEnabled = on
            settings.data.polishSkipped = false
            if on { Task { await ollama.ensureRunning(); await ollama.prepareIfActive() } } else { ollama.stop() }
        })
    }
}

enum PolishCopy {
    static let why = "Speech-to-text types exactly what you say, including “um”, repeated words, and “Tuesday, no wait, Wednesday”. AI polish reads each sentence and writes what you meant: clean punctuation, filler words gone, corrections applied. It runs on your Mac (nothing is sent to the internet), it's free, and it adds about half a second."
    static func size(for m: String) -> String {
        switch m {
        case "qwen2.5:3b", "llama3.2:3b": return "2 GB"
        case "qwen2.5:1.5b": return "1 GB"
        case "gemma3:1b": return "0.8 GB"
        default: return "download"
        }
    }
    static func label(for m: String) -> String {
        switch m {
        case "qwen2.5:3b": return "Recommended · Qwen 2.5 3B · 2 GB download"
        case "qwen2.5:1.5b": return "Faster, less accurate · Qwen 2.5 1.5B · 1 GB"
        case "llama3.2:3b": return "Alternative · Llama 3.2 3B · 2 GB"
        case "gemma3:1b": return "Tiny · Gemma 3 1B · 0.8 GB"
        default: return m
        }
    }
}

/// Shows download / running state for the polish model with a single obvious action.
struct PolishStatusRow: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var ollama = OllamaManager.shared

    var body: some View {
        HStack(spacing: 10) {
            switch ollama.status {
            case .pulling(let p, let msg):
                ProgressView(value: p).frame(width: 160)
                Text("\(Int(p * 100))% · \(msg)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            case .starting:
                ProgressView().controlSize(.small)
                Text("Starting the AI engine… (up to 30 seconds the first time)").foregroundStyle(.secondary)
            case .error(let e):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(e).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await ollama.ensureRunning() } }.controlSize(.small)
            case .off, .ready:
                if settings.data.polishReady && (ollama.hasModel(settings.data.ollamaModel) || !ollama.isReady) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready. Polish runs on every dictation.")
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.orange)
                    Text("Not downloaded yet.")
                    Button("Download AI Polish (\(PolishCopy.size(for: settings.data.ollamaModel)))") {
                        Task {
                            await ollama.ensureRunning()
                            guard ollama.isReady else { return }
                            if ollama.hasModel(settings.data.ollamaModel) { settings.data.polishReady = true }
                            else { await ollama.pull(model: settings.data.ollamaModel) }
                            await ollama.prepareIfActive()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - History

struct HistoryTab: View {
    @ObservedObject var history = HistoryStore.shared
    @State private var search = ""

    var filtered: [HistoryEntry] {
        search.isEmpty ? history.entries : history.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search your dictations", text: $search).textFieldStyle(.roundedBorder)
                Button("Clear all", role: .destructive) { history.clear() }.disabled(history.entries.isEmpty)
            }
            .padding(14)
            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(history.entries.isEmpty ? "Everything you dictate is saved here, on this Mac only." : "No matches").foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filtered) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.text).textSelection(.enabled)
                        HStack {
                            Text(e.date, style: .relative) + Text(" ago")
                            if !e.appName.isEmpty { Text("· \(e.appName)") }
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(e.text, forType: .string)
                            }.controlSize(.mini)
                            Button { history.delete(e) } label: { Image(systemName: "trash") }.controlSize(.mini)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
