import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable, Hashable {
    case home, shortcut, transcription, cleanup, history, permissions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .shortcut: return "Shortcut & Behavior"
        case .transcription: return "Speech Model"
        case .cleanup: return "Cleanup & AI Polish"
        case .history: return "History"
        case .permissions: return "Permissions & About"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .shortcut: return "keyboard"
        case .transcription: return "waveform"
        case .cleanup: return "wand.and.stars"
        case .history: return "clock"
        case .permissions: return "lock.shield"
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
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
        } detail: {
            Group {
                switch holder.page {
                case .home: HomePage(holder: holder)
                case .shortcut: GeneralTab()
                case .transcription: TranscriptionTab()
                case .cleanup: CleanupTab()
                case .history: HistoryTab()
                case .permissions: PermissionsTab()
                }
            }
            .navigationTitle(holder.page.title)
        }
        .frame(minWidth: 860, minHeight: 600)
    }
}

// MARK: - Home

struct HomePage: View {
    @ObservedObject var holder: PageHolder
    @ObservedObject var settings = Settings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var controller = DictationController.shared
    @State private var mic = Permissions.microphoneGranted
    @State private var ax = Permissions.accessibilityGranted
    @State private var tryText = ""
    @FocusState private var tryFocused: Bool
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var model: WhisperModel { WhisperModel.byId(settings.data.modelId) }
    private var modelReady: Bool { models.isDownloaded(model) }
    private var allDone: Bool { mic && ax && modelReady }
    private var s: SettingsData { settings.data }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if allDone { readyBanner } else { setupCard }
                howToCard
                tryCard
                footer
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .onReceive(timer) { _ in
            mic = Permissions.microphoneGranted
            ax = Permissions.accessibilityGranted
            if ax, !controller.hotkeys.isRunning { _ = controller.startHotkeys() }
            if modelReady, !WhisperEngine.shared.isLoaded, !controller.modelStatus.hasPrefix("Loading") { controller.preloadModel() }
            if allDone, !s.hasCompletedOnboarding { settings.data.hasCompletedOnboarding = true }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("talkatanormalvolumeflow").font(.system(size: 26, weight: .bold))
                Text("Hold a key. Talk normally. Let go. Your words appear wherever your cursor is.")
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private var readyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're all set.").font(.headline)
                Text("The app keeps running in your menu bar (look for the mic icon at the top right of your screen). You can close this window.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finish setup (3 steps)").font(.headline)
            setupRow(1, "Allow microphone access", done: mic,
                     detail: "So the app can hear you. Click the button, then click Allow in the macOS prompt.",
                     button: "Allow Microphone") {
                Task { _ = await Permissions.requestMicrophone(); mic = Permissions.microphoneGranted
                    if !mic { Permissions.openMicrophoneSettings() } }
            }
            setupRow(2, "Allow accessibility access", done: ax,
                     detail: "Lets the app notice your shortcut key in any app and type the text for you. Click the button, then turn ON the switch next to talkatanormalvolumeflow in the System Settings window that opens.",
                     button: "Open Accessibility Settings") {
                Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
            }
            setupRow(3, "Download the speech model", done: modelReady,
                     detail: "\(model.name), \(model.sizeMB) MB. One-time download, stored on this Mac. Your voice is never uploaded anywhere.",
                     button: "Download") { models.download(model) }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func setupRow(_ n: Int, _ title: String, done: Bool, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 30, height: 30)
                if done { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).strikethrough(done, color: .secondary)
                if !done {
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if n == 3, let p = models.progress[model.id] {
                        HStack { ProgressView(value: p).frame(width: 220); Text("\(Int(p * 100))%").monospacedDigit() }
                    } else {
                        Button(button, action: action).buttonStyle(.borderedProminent).padding(.top, 2)
                        if n == 3, let e = models.errors[model.id] { Text(e).font(.caption).foregroundStyle(.red) }
                    }
                } else {
                    Text("Done").font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
        }
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How to dictate").font(.headline)
            HStack(spacing: 0) {
                stepBox(icon: "hand.point.up.left.fill", title: s.mode == .hold ? "Hold" : "Press",
                        subtitle: s.shortcut.name, highlight: true)
                arrow
                stepBox(icon: "mic.fill", title: "Talk", subtitle: "at a normal volume")
                arrow
                stepBox(icon: "hand.raised.fill", title: s.mode == .hold ? "Let go" : "Press again", subtitle: "text appears in ~1 second")
            }
            VStack(alignment: .leading, spacing: 6) {
                bullet("Click into any text box first (Slack, email, Notes, anywhere). The text goes where your cursor is.")
                bullet("Press **Esc** while talking to cancel.")
                bullet("Say **“new line”**, **“new paragraph”**, or **“scratch that”** to edit as you go.")
                if s.shortcut.keyCode == 63 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Stop the emoji picker from popping up: in System Settings → Keyboard, set **“Press 🌐 key to”** to **Do Nothing**.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }.controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            HStack {
                Button("Change shortcut or mode…") { holder.page = .shortcut }
                Spacer()
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.title3).foregroundStyle(.secondary).padding(.horizontal, 10)
    }

    private func stepBox(icon: String, title: String, subtitle: String, highlight: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(highlight ? Color.accentColor : .secondary)
            Text(title).font(.system(size: 17, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(highlight ? Color.accentColor : .secondary).multilineTextAlignment(.center)
                .fontWeight(highlight ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(12)
        .background(highlight ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try it right here").font(.headline)
            Text(allDone ? "Click in the box below, then \(s.mode == .hold ? "hold" : "press") **\(s.shortcut.name)** and say something."
                         : "Finish the 3 setup steps above first.")
                .foregroundStyle(.secondary)
            TextEditor(text: $tryText)
                .font(.system(size: 15))
                .frame(height: 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tryFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: tryFocused ? 2 : 1))
                .focused($tryFocused)
                .disabled(!allDone)
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
        switch controller.state {
        case .recording: Label("Listening…", systemImage: "circle.fill").foregroundStyle(.red)
        case .processing(let m): Label(m, systemImage: "ellipsis.circle").foregroundStyle(.secondary)
        case .notice(let m): Label(m, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        case .idle: Label(controller.modelStatus, systemImage: "circle.fill").foregroundStyle(modelReady && WhisperEngine.shared.isLoaded ? .green : .secondary).font(.caption)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Toggle("Open automatically when I log in", isOn: launchAtLogin)
            Spacer()
            Text("Free · open source · 100% on your Mac").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { settings.data.launchAtLogin }, set: { on in
            settings.data.launchAtLogin = on
            LaunchAtLogin.set(on)
        })
    }
}
