import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable, Hashable {
    case home, shortcut, transcription, cleanup, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .shortcut: return "Shortcut"
        case .transcription: return "Accuracy"
        case .cleanup: return "AI Polish"
        case .history: return "History"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .shortcut: return "keyboard"
        case .transcription: return "waveform"
        case .cleanup: return "wand.and.stars"
        case .history: return "clock"
        }
    }
}

final class PageHolder: ObservableObject { @Published var page: Page = .home }

struct MainView: View {
    @ObservedObject var holder: PageHolder

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $holder.page) { p in
                Label(p.title, systemImage: p.icon).tag(p)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 210)
        } detail: {
            Group {
                switch holder.page {
                case .home: HomePage(holder: holder)
                case .shortcut: GeneralTab()
                case .transcription: TranscriptionTab()
                case .cleanup: CleanupTab()
                case .history: HistoryTab()
                }
            }
            .navigationTitle(holder.page.title)
        }
        .frame(minWidth: 820, minHeight: 600)
        .tint(Theme.accent)
    }
}

// MARK: - Home

/// Two states, both designed to fit in the window without scrolling:
/// 1. Setup: one step at a time (finished steps collapse to a line, later steps are greyed).
/// 2. Ready: how-to strip + a box to try it in.
struct HomePage: View {
    @ObservedObject var holder: PageHolder
    @ObservedObject var settings = Settings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var controller = DictationController.shared
    @ObservedObject var ollama = OllamaManager.shared
    @ObservedObject var updater = Updater.shared
    @State private var mic = Permissions.microphoneGranted
    @State private var ax = Permissions.accessibilityGranted
    @State private var tryText = ""
    @FocusState private var tryFocused: Bool
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var model: WhisperModel { WhisperModel.byId(settings.data.modelId) }
    private var modelReady: Bool { models.isDownloaded(model) }
    private var s: SettingsData { settings.data }
    private var polishDone: Bool { s.polishReady || s.polishSkipped || !s.ollamaEnabled }
    private var requiredDone: Bool { mic && ax && modelReady }
    private var allDone: Bool { requiredDone && polishDone }

    var body: some View {
        PageScroll {
            header
            updateBanner
            if allDone {
                howToCard
                tryCard
            } else {
                setupCard
            }
            footer
        }
        .onAppear {
            controller.localInsertHandler = { [self] text in
                guard allDone else { return false }
                tryText += text
                return true
            }
        }
        .onDisappear { controller.localInsertHandler = nil }
        .onReceive(timer) { _ in
            mic = Permissions.microphoneGranted
            ax = Permissions.accessibilityGranted
            if ax, !controller.hotkeys.isRunning { _ = controller.startHotkeys() }
            if modelReady, !WhisperEngine.shared.isLoaded, !controller.modelStatus.hasPrefix("Loading") { controller.preloadModel() }
            if allDone, !s.hasCompletedOnboarding { settings.data.hasCompletedOnboarding = true }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text("talkatanormalvolumeflow").font(.system(size: 22, weight: .bold))
                Text(s.shortcut.isMouseButton
                     ? "Hold a mouse button. Talk normally. Let go. Your words appear wherever your cursor is."
                     : "Hold a key. Talk normally. Let go. Your words appear wherever your cursor is.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: updates

    @ViewBuilder private var updateBanner: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking:
            bannerRow(icon: "arrow.triangle.2.circlepath", color: .secondary) { Text("Checking for updates…").foregroundStyle(.secondary) }
        case .upToDate:
            bannerRow(icon: "checkmark.circle.fill", color: .green) { Text("You have the latest version (\(Updater.currentVersion)).") }
        case .available(let v, _):
            bannerRow(icon: "arrow.down.circle.fill", color: Theme.accent) {
                Text("Version \(v) is available.").fontWeight(.semibold)
                Text("You have \(Updater.currentVersion). The app will restart.").foregroundStyle(.secondary)
                Spacer()
                Button(Updater.canSelfUpdate ? "Update Now" : "Get It") { updater.installAvailable() }.buttonStyle(.borderedProminent)
            }
        case .downloading:
            bannerRow(icon: "arrow.down.circle", color: Theme.accent) { ProgressView().controlSize(.small); Text("Downloading the update…") }
        case .installing:
            bannerRow(icon: "gearshape.fill", color: Theme.accent) { ProgressView().controlSize(.small); Text("Installing… the app will reopen in a moment.") }
        case .error(let e):
            bannerRow(icon: "exclamationmark.triangle.fill", color: .orange) {
                Text(e).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Open Download Page") { NSWorkspace.shared.open(Updater.releasesPage) }
            }
        }
    }

    private func bannerRow<C: View>(icon: String, color: Color, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: setup

    private var currentStep: Int {
        if !mic { return 1 }
        if !ax { return 2 }
        if !modelReady { return 3 }
        return 4
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let's set it up").font(.headline)
            setupRow(1, "Allow the microphone", done: mic,
                     detail: "So the app can hear you. Click the button, then click Allow.") {
                Button("Allow Microphone") {
                    Task { _ = await Permissions.requestMicrophone(); mic = Permissions.microphoneGranted
                        if !mic { Permissions.openMicrophoneSettings() } }
                }.buttonStyle(.borderedProminent)
            }
            setupRow(2, "Allow accessibility", done: ax,
                     detail: "Lets the app notice your shortcut and type for you. Click the button, then turn ON the switch next to talkatanormalvolumeflow.") {
                Button("Open Accessibility Settings") { Permissions.promptAccessibility(); Permissions.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
            }
            setupRow(3, "Download the speech recognizer", done: modelReady,
                     detail: "About \(model.sizeMB) MB, one time. It lives on this Mac, so your voice is never uploaded.") {
                if let p = models.progress[model.id] {
                    HStack { ProgressView(value: p).frame(width: 220); Text("\(Int(p * 100))%").monospacedDigit() }
                } else {
                    Button("Download") { models.download(model) }.buttonStyle(.borderedProminent)
                    if let e = models.errors[model.id] { Text(e).font(.caption).foregroundStyle(.red) }
                }
            }
            setupRow(4, "Add AI polish (recommended)", done: polishDone,
                     detail: PolishCopy.short + " About 2 GB, one time.") {
                polishAction
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var polishAction: some View {
        switch ollama.status {
        case .pulling(let p, let msg):
            HStack { ProgressView(value: p).frame(width: 220); Text("\(Int(p * 100))%").monospacedDigit(); Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .starting:
            HStack { ProgressView().controlSize(.small); Text("Getting ready… (up to 30 seconds the first time)").foregroundStyle(.secondary) }
        case .error(let e):
            VStack(alignment: .leading, spacing: 6) {
                Text(e).font(.caption).foregroundStyle(.red)
                HStack { Button("Retry") { startPolishDownload() }; Button("Skip for now") { skipPolish() } }
            }
        case .off, .ready:
            HStack(spacing: 10) {
                Button("Download AI Polish") { startPolishDownload() }.buttonStyle(.borderedProminent)
                Button("Skip for now") { skipPolish() }
            }
        }
    }

    private func startPolishDownload() {
        settings.data.ollamaEnabled = true
        settings.data.polishSkipped = false
        Task {
            await ollama.ensureRunning()
            guard ollama.isReady else { return }
            if ollama.hasModel(s.ollamaModel) { settings.data.polishReady = true }
            else { await ollama.pull(model: s.ollamaModel) }
            await ollama.prepareIfActive()
        }
    }

    private func skipPolish() {
        settings.data.polishSkipped = true
        ollama.stop()
    }

    /// Only the current step shows its explanation and button; done steps are a single line; later steps are dimmed.
    @ViewBuilder
    private func setupRow<A: View>(_ n: Int, _ title: String, done: Bool, detail: String, @ViewBuilder action: () -> A) -> some View {
        let active = n == currentStep && !done
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Color.green) : (active ? AnyShapeStyle(Theme.wash) : AnyShapeStyle(Color.secondary.opacity(0.3)))).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: active ? .semibold : .regular))
                    .foregroundStyle(done || active ? .primary : .secondary)
                if active {
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    action().padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    // MARK: ready

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                stepBox(icon: s.shortcut.symbol, title: s.mode == .hold ? "Hold" : "Press",
                        subtitle: s.shortcut.displayName, highlight: true)
                arrow
                stepBox(icon: "mic.fill", title: "Talk", subtitle: "at a normal volume")
                arrow
                stepBox(icon: "text.cursor", title: s.mode == .hold ? "Let go" : "Press again", subtitle: "your words appear")
            }
            Text("Works in any app: click where you want the text first. Press **Esc** to cancel. Say **“new line”** or **“scratch that”** while talking.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if s.shortcut.keyCode == 63, !s.shortcut.isMouseButton {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    Text("If the emoji picker pops up: in System Settings → Keyboard, set **“Press 🌐 key to”** to **Do Nothing**.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Open") { Permissions.openKeyboardSettings() }.controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.title3).foregroundStyle(.secondary).padding(.horizontal, 10)
    }

    private func stepBox(icon: String, title: String, subtitle: String, highlight: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(highlight ? AnyShapeStyle(Theme.wave) : AnyShapeStyle(.secondary))
            Text(title).font(.system(size: 16, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(highlight ? Theme.accent : .secondary).multilineTextAlignment(.center)
                .fontWeight(highlight ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(10)
        .background(highlight ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay { if highlight { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.wave, lineWidth: 1.5) } }
    }

    private var tryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Try it").font(.headline)
                Text("Click in the box, then \(s.mode == .hold ? "hold" : "press") **\(s.shortcut.displayName)** and say something.")
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $tryText)
                .font(.system(size: 15))
                .frame(minHeight: 80, maxHeight: 140)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tryFocused ? AnyShapeStyle(Theme.wave) : AnyShapeStyle(Color.secondary.opacity(0.3)), lineWidth: tryFocused ? 2 : 1))
                .focused($tryFocused)
            HStack {
                statusPill
                Spacer()
                Button("Clear") { tryText = "" }.disabled(tryText.isEmpty)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var statusPill: some View {
        Group {
            switch controller.state {
            case .recording: Label("Listening…", systemImage: "circle.fill").foregroundStyle(.red)
            case .processing(let m): Label(m, systemImage: "ellipsis.circle").foregroundStyle(.secondary)
            case .notice(let m): Label(m, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            case .idle:
                let loaded = modelReady && WhisperEngine.shared.isLoaded
                HStack(spacing: 12) {
                    Label(loaded ? "Ready" : controller.modelStatus, systemImage: "circle.fill").foregroundStyle(loaded ? .green : .secondary)
                    Label(s.polishActive ? "AI polish on" : "AI polish off", systemImage: "wand.and.stars")
                        .foregroundStyle(s.polishActive ? .green : .secondary)
                }
            }
        }
        .font(.caption)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if allDone {
                Text("You can close this window. The app keeps running as a mic icon in your menu bar.")
            } else {
                Text(mic ? "Microphone ✓" : "Microphone ✗").foregroundStyle(mic ? .green : .red)
                Text(ax ? "Accessibility ✓" : "Accessibility ✗").foregroundStyle(ax ? .green : .red)
            }
            Spacer()
            Text("Free · Private · Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
