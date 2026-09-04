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

/// Content hugs the left edge (next to the sidebar) instead of floating in the middle of a wide window.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shortcut & Behavior

struct GeneralTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false

    var body: some View {
        PageScroll {
            Card(title: "Your shortcut", subtitle: "The key or mouse button you hold to dictate. It works in every app.") {
                HStack(spacing: 10) {
                    ForEach(Shortcut.presets, id: \.self) { p in presetButton(p) }
                }
                Text("Or a mouse button (the extra buttons on a Logitech MX Master, for example):").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(Shortcut.mousePresets, id: \.self) { p in presetButton(p) }
                }
                HStack {
                    Text("Current:").foregroundStyle(.secondary)
                    Text(settings.data.shortcut.displayName).fontWeight(.semibold)
                    Spacer()
                    Button(recording ? "Press a key or click a mouse button now…" : "Use something else…") { record() }.disabled(recording)
                }
                if settings.data.shortcut.isMouseButton {
                    tip("If you use Logi Options+ or similar software, that software may grab the button first. Either leave the button unassigned there, or have it send a keystroke (like F13) and record that keystroke here.")
                }
                if settings.data.shortcut.keyCode == 63, !settings.data.shortcut.isMouseButton {
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
            Card(title: "How the shortcut works") {
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
            Text("If the shortcut stops working after an update: remove the app from System Settings → Privacy & Security → Accessibility and add it back.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func presetButton(_ p: Shortcut) -> some View {
        Button { settings.data.shortcut = p } label: { Text(p.displayName).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
            .tint(settings.data.shortcut == p ? .accentColor : nil)
            .controlSize(.large)
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
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
        DictationController.shared.hotkeys.recorder = { input in
            DispatchQueue.main.async {
                recording = false
                switch input {
                case .mouseButton(let b):
                    settings.data.shortcut = .mouse(b)
                case .key(let keyCode, let flags, let isModifier):
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
}

// MARK: - Accuracy & Language

/// Two plain-English choices (Standard / Extra accurate) plus a language switch. The actual model file is picked
/// for this Mac behind the scenes; options this Mac can't run well are never shown.
struct TranscriptionTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var controller = DictationController.shared

    private var current: WhisperModel { WhisperModel.byId(settings.data.modelId) }
    private var otherLanguage: Bool { !current.englishOnly }
    /// The tier the user has chosen (or is downloading towards).
    private var chosenTier: WhisperModel.Tier {
        if let p = models.pendingSwitch { return WhisperModel.byId(p).tier }
        return current.tier
    }

    var body: some View {
        PageScroll {
            Card(title: "Accuracy", subtitle: "Everything happens on this Mac. Your voice never leaves your computer.") {
                ForEach(WhisperModel.availableTiers) { tier in
                    tierRow(tier)
                    if tier != WhisperModel.availableTiers.last { Divider() }
                }
                if WhisperModel.availableTiers.count == 1 {
                    Text("This Mac has \(Machine.memoryGB) GB of memory, so only Standard is offered here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card(title: "Language") {
                Toggle("I dictate in a language other than English", isOn: otherLanguageBinding)
                if otherLanguage {
                    Picker("Which language?", selection: $settings.data.language) {
                        Text("Let it figure it out").tag("auto")
                        ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .frame(maxWidth: 360)
                }
            }
        }
    }

    @ViewBuilder
    private func tierRow(_ tier: WhisperModel.Tier) -> some View {
        let target = WhisperModel.pick(tier: tier, englishOnly: !otherLanguage)
        let selected = chosenTier == tier
        let downloading = models.progress[target.id]
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 18)).foregroundStyle(selected ? Color.accentColor : .secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tier.title).font(.system(size: 15, weight: .semibold))
                    if tier == .standard { badge("Recommended") }
                    if selected, current.id == target.id, models.isDownloaded(target) { badge("In use", color: .green) }
                }
                Text(tier.blurb).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let p = downloading {
                    HStack {
                        ProgressView(value: p).frame(width: 200)
                        Text("\(Int(p * 100))%").font(.caption).monospacedDigit()
                        Button("Cancel") { models.cancel(target) }.controlSize(.small)
                    }
                } else if !models.isDownloaded(target) {
                    Text("Needs a one-time \(target.sizeMB >= 1000 ? String(format: "%.1f GB", Double(target.sizeMB) / 1024) : "\(target.sizeMB) MB") download.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let e = models.errors[target.id] { Text(e).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { if !selected || current.id != target.id { models.use(target) } }
    }

    private func badge(_ text: String, color: Color = .accentColor) -> some View {
        Text(text).font(.caption2).bold().padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
    }

    private var otherLanguageBinding: Binding<Bool> {
        Binding(get: { otherLanguage }, set: { on in
            if on, settings.data.language == "en" { settings.data.language = "auto" }
            if !on { settings.data.language = "en" }
            models.use(WhisperModel.pick(tier: chosenTier, englishOnly: !on))
        })
    }

    static let languages: [(String, String)] = [
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt", "Portuguese"), ("it", "Italian"),
        ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("tr", "Turkish"), ("ar", "Arabic"),
        ("hi", "Hindi"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("vi", "Vietnamese"), ("tl", "Tagalog"),
        ("sv", "Swedish"), ("da", "Danish"), ("no", "Norwegian"), ("fi", "Finnish"),
    ]
}

// MARK: - AI Polish

struct CleanupTab: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var ollama = OllamaManager.shared
    @State private var newFrom = ""
    @State private var newTo = ""

    var body: some View {
        PageScroll {
            Card(title: "AI polish", subtitle: PolishCopy.short) {
                Toggle("Polish my dictations", isOn: polishToggle).toggleStyle(.switch)
                if settings.data.ollamaEnabled && !settings.data.polishSkipped { PolishStatusRow() }
            }
            Card(title: "Always-on cleanup", subtitle: "Quick fixes that happen every time, even with AI polish off.") {
                Toggle("Remove “um”, “uh”, “hmm”", isOn: $settings.data.removeFillers)
                Toggle("Voice commands: “new line”, “new paragraph”, “scratch that”", isOn: $settings.data.voiceCommands)
            }
            Card(title: "Words it gets wrong", subtitle: "Teach it names and terms it keeps mishearing.") {
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
                    TextField("It hears… (e.g. zen made)", text: $newFrom)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("It should write… (e.g. ZenMaid)", text: $newTo)
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
    /// One idea per sentence, no jargon. Used on the Home setup step and the AI Polish page.
    static let short = "Normally you get exactly what you said, “um”s and all. AI polish tidies each sentence into what you meant: fixes punctuation, drops the “um”s, and applies corrections like “Tuesday, no wait, Wednesday”. It's free, runs on your Mac, and adds about half a second."
    static func size(for m: String) -> String {
        switch m {
        case "qwen2.5:3b", "llama3.2:3b": return "2 GB"
        case "qwen2.5:1.5b": return "1 GB"
        case "gemma3:1b": return "0.8 GB"
        default: return "download"
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
                Text("Getting ready… (up to 30 seconds the first time)").foregroundStyle(.secondary)
            case .error(let e):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(e).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await ollama.ensureRunning() } }.controlSize(.small)
            case .off, .ready:
                if settings.data.polishReady && (ollama.hasModel(settings.data.ollamaModel) || !ollama.isReady) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready. Every dictation gets polished.")
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.orange)
                    Text("Needs a one-time download.")
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
