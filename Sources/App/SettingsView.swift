import SwiftUI
import ServiceManagement

enum SettingsTab: String, Hashable { case general, transcription, cleanup, history, permissions }

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @Binding var tab: SettingsTab

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "keyboard") }.tag(SettingsTab.general)
            TranscriptionTab().tabItem { Label("Transcription", systemImage: "waveform") }.tag(SettingsTab.transcription)
            CleanupTab().tabItem { Label("Cleanup", systemImage: "wand.and.stars") }.tag(SettingsTab.cleanup)
            HistoryTab().tabItem { Label("History", systemImage: "clock") }.tag(SettingsTab.history)
            PermissionsTab().tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(SettingsTab.permissions)
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Preset", selection: presetBinding) {
                    ForEach(Shortcut.presets, id: \.self) { Text($0.name).tag(Optional($0)) }
                    Text("Custom…").tag(Optional<Shortcut>.none)
                }
                HStack {
                    Text("Current shortcut")
                    Spacer()
                    Text(settings.data.shortcut.name).fontWeight(.semibold).foregroundStyle(.secondary)
                    Button(recording ? "Press a key…" : "Record") { record() }
                        .disabled(recording)
                }
                Picker("Mode", selection: $settings.data.mode) {
                    ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if settings.data.shortcut.keyCode == 63 {
                    Text("Tip: set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing, so macOS doesn't also open the emoji picker.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }.controlSize(.small)
                }
            }
            Section("Behavior") {
                Toggle("Launch at login", isOn: launchAtLogin)
                Toggle("Show floating indicator while dictating", isOn: $settings.data.showOverlay)
                Toggle("Play start / stop sounds", isOn: $settings.data.playSounds)
                Toggle("Add a space after inserted text", isOn: $settings.data.trailingSpace)
                Toggle("Save dictation history on this Mac", isOn: $settings.data.historyEnabled)
            }
            Section("Text insertion") {
                Picker("Method", selection: $settings.data.insertMethod) {
                    ForEach(InsertMethod.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Restore previous clipboard after pasting", isOn: $settings.data.restoreClipboard)
                    .disabled(settings.data.insertMethod != .paste)
            }
        }
        .formStyle(.grouped)
    }

    private var presetBinding: Binding<Shortcut?> {
        Binding(
            get: { Shortcut.presets.first { $0 == settings.data.shortcut } },
            set: { if let s = $0 { settings.data.shortcut = s } else { record() } }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { settings.data.launchAtLogin }, set: { on in
            settings.data.launchAtLogin = on
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("Launch at login failed: \(error)") }
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
                                                          name: Shortcut.describe(keyCode: keyCode, flags: []))
                    }
                } else {
                    if keyCode == 53 { return } // Escape cancels recording
                    settings.data.shortcut = Shortcut(keyCode: keyCode, modifiers: flags.rawValue, isModifierKey: false,
                                                      name: Shortcut.describe(keyCode: keyCode, flags: flags))
                }
            }
        }
    }
}

// MARK: - Transcription

struct TranscriptionTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var controller = DictationController.shared

    var body: some View {
        Form {
            Section {
                Text("Everything runs on this Mac with whisper.cpp — audio never leaves your computer.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Status", value: controller.modelStatus)
            }
            Section("Speech model") {
                ForEach(WhisperModel.all) { m in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(m.name).fontWeight(settings.data.modelId == m.id ? .semibold : .regular)
                                if settings.data.modelId == m.id {
                                    Text("ACTIVE").font(.caption2).bold().padding(.horizontal, 5).padding(.vertical, 1)
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
                }
            }
            Section("Language") {
                Picker("Spoken language", selection: $settings.data.language) {
                    Text("Auto-detect (multilingual models only)").tag("auto")
                    ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                if WhisperModel.byId(settings.data.modelId).englishOnly, settings.data.language != "en" {
                    Text("The active model is English-only; pick a “Multilingual” model for other languages.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    static let languages: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt", "Portuguese"), ("it", "Italian"),
        ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("tr", "Turkish"), ("ar", "Arabic"),
        ("hi", "Hindi"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("vi", "Vietnamese"), ("tl", "Tagalog"),
        ("sv", "Swedish"), ("da", "Danish"), ("no", "Norwegian"), ("fi", "Finnish"),
    ]
}

// MARK: - Cleanup

struct CleanupTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var ollama = OllamaManager.shared
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var customModel = ""

    var body: some View {
        Form {
            Section("Built-in cleanup (instant, always on device)") {
                Toggle("Remove filler words", isOn: $settings.data.removeFillers)
                TextField("Filler words (comma separated)", text: fillerBinding)
                    .disabled(!settings.data.removeFillers)
                Toggle("Voice commands: “new line”, “new paragraph”, “scratch that”", isOn: $settings.data.voiceCommands)
                Toggle("Smart capitalization", isOn: $settings.data.smartCapitalization)
            }
            Section("Custom vocabulary & replacements") {
                Text("Fix words Whisper mishears (e.g. “zen made” → “ZenMaid”). These also bias recognition toward your terms.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(settings.data.replacements) { r in
                    HStack {
                        Text(r.from).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(r.to).frame(maxWidth: .infinity, alignment: .leading)
                        Button { settings.data.replacements.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Heard as", text: $newFrom)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Should be", text: $newTo)
                    Button("Add") {
                        settings.data.replacements.append(Replacement(from: newFrom.trimmingCharacters(in: .whitespaces), to: newTo.trimmingCharacters(in: .whitespaces)))
                        newFrom = ""; newTo = ""
                    }
                    .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("AI polish (optional, free, on device via Ollama)") {
                Toggle("Rewrite with a local AI model", isOn: $settings.data.ollamaEnabled)
                    .onChange(of: settings.data.ollamaEnabled) { _, on in
                        if on { Task { await ollama.ensureRunning() } } else { ollama.stop() }
                    }
                Text("Fixes grammar, applies “no wait, I meant…” corrections, and removes rambling. Adds about half a second (a few seconds the first time while the model loads). The app works fully without it.")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.data.ollamaEnabled {
                    LabeledContent("Engine") { statusView }
                    Picker("Model", selection: modelBinding) {
                        ForEach(OllamaManager.suggestedModels, id: \.self) { Text(label(for: $0)).tag($0) }
                        if !OllamaManager.suggestedModels.contains(settings.data.ollamaModel) {
                            Text(settings.data.ollamaModel).tag(settings.data.ollamaModel)
                        }
                    }
                    HStack {
                        TextField("Or any Ollama model name, e.g. llama3.1:8b", text: $customModel)
                        Button("Use") { settings.data.ollamaModel = customModel.trimmingCharacters(in: .whitespaces); customModel = "" }
                            .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        if ollama.hasModel(settings.data.ollamaModel) {
                            Label("\(settings.data.ollamaModel) is installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("\(settings.data.ollamaModel) not downloaded yet", systemImage: "arrow.down.circle").foregroundStyle(.orange)
                            Spacer()
                            Button("Download model") { Task { await ollama.pull(model: settings.data.ollamaModel) } }
                                .disabled(!ollama.isReady)
                        }
                    }
                    TextField("Style instructions", text: $settings.data.ollamaStyle, axis: .vertical).lineLimit(2...4)
                }
            }
        }
        .formStyle(.grouped)
        .task { if settings.data.ollamaEnabled { await ollama.ensureRunning() } }
    }

    private func label(for m: String) -> String {
        switch m {
        case "qwen2.5:1.5b": return "Qwen 2.5 1.5B — fastest, ~1 GB"
        case "gemma3:1b": return "Gemma 3 1B — tiny, ~0.8 GB"
        case "llama3.2:3b": return "Llama 3.2 3B — better quality, ~2 GB"
        case "qwen2.5:3b": return "Qwen 2.5 3B — best balance, ~2 GB (recommended)"
        default: return m
        }
    }

    private var modelBinding: Binding<String> {
        Binding(get: { settings.data.ollamaModel }, set: { settings.data.ollamaModel = $0 })
    }

    @ViewBuilder private var statusView: some View {
        switch ollama.status {
        case .off: Text("Off").foregroundStyle(.secondary)
        case .starting: HStack { ProgressView().controlSize(.small); Text("Starting…") }
        case .ready(let which): Label("Running (\(which))", systemImage: "circle.fill").foregroundStyle(.green)
        case .pulling(let p, let msg):
            HStack { ProgressView(value: p).frame(width: 100); Text("\(Int(p * 100))% \(msg)").font(.caption).lineLimit(1) }
        case .error(let e): Text(e).foregroundStyle(.red).font(.caption)
        }
    }

    private var fillerBinding: Binding<String> {
        Binding(get: { settings.data.fillerWords.joined(separator: ", ") },
                set: { settings.data.fillerWords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
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
                TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                Button("Clear all", role: .destructive) { history.clear() }.disabled(history.entries.isEmpty)
            }
            .padding(10)
            if filtered.isEmpty {
                Spacer()
                Text(history.entries.isEmpty ? "Your dictations will show up here." : "No matches").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.text).textSelection(.enabled)
                        HStack {
                            Text(e.date, style: .relative) + Text(" ago")
                            if !e.appName.isEmpty { Text("· \(e.appName)") }
                            Text("· \(String(format: "%.1fs", e.durationSeconds))")
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

// MARK: - Permissions

struct PermissionsTab: View {
    @State private var mic = Permissions.microphoneGranted
    @State private var ax = Permissions.accessibilityGranted
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                row("Microphone", ok: mic, why: "To hear you.") {
                    Task { _ = await Permissions.requestMicrophone(); mic = Permissions.microphoneGranted }
                    if !mic { Permissions.openMicrophoneSettings() }
                }
                row("Accessibility", ok: ax, why: "To detect your shortcut key in any app and to paste the text.") {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
            Section {
                Text("If you rebuilt or updated the app and the shortcut stopped working, remove talkatanormalvolumeflow from the Accessibility list and add it again.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Shortcut listener", value: DictationController.shared.hotkeys.isRunning ? "Active" : "Not running (grant Accessibility, then relaunch)")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                Text("talkatanormalvolumeflow is free, open source, and 100% on-device. Speech recognition by whisper.cpp; optional polish by Ollama.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            mic = Permissions.microphoneGranted
            ax = Permissions.accessibilityGranted
            if ax, !DictationController.shared.hotkeys.isRunning { _ = DictationController.shared.startHotkeys() }
        }
    }

    private func row(_ name: String, ok: Bool, why: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading) { Text(name); Text(why).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !ok { Button("Grant…", action: action) }
        }
    }
}
