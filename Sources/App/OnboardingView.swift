import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var models = ModelManager.shared
    @State private var mic = Permissions.microphoneGranted
    @State private var ax = Permissions.accessibilityGranted
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var onDone: () -> Void

    private var model: WhisperModel { WhisperModel.byId(settings.data.modelId) }
    private var modelReady: Bool { models.isDownloaded(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "mic.circle.fill").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("talkatanormalvolumeflow").font(.title2).bold()
                    Text("Hold a key, talk, release. Your words appear wherever your cursor is. Free, private, on-device.")
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Microphone access", done: mic, detail: "So the app can hear you.") {
                Button("Allow microphone") {
                    Task { _ = await Permissions.requestMicrophone(); mic = Permissions.microphoneGranted
                        if !mic { Permissions.openMicrophoneSettings() } }
                }
            }
            step(2, "Accessibility access", done: ax, detail: "Lets the app see your shortcut key in any app and paste the text. macOS will show a prompt; toggle the app on in System Settings.") {
                Button("Open Accessibility settings") { Permissions.promptAccessibility(); Permissions.openAccessibilitySettings() }
            }
            step(3, "Download the speech model", done: modelReady, detail: "\(model.name), \(model.sizeMB) MB, one-time download. Stored on this Mac.") {
                if let p = models.progress[model.id] {
                    HStack { ProgressView(value: p).frame(width: 160); Text("\(Int(p * 100))%").monospacedDigit() }
                } else {
                    Button("Download") { models.download(model) }
                    if let e = models.errors[model.id] { Text(e).font(.caption).foregroundStyle(.red) }
                }
            }

            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your shortcut is **\(settings.data.shortcut.name)** (\(settings.data.mode == .hold ? "hold to talk" : "press to toggle")). Change it any time in Settings.")
                    if settings.data.shortcut.keyCode == 63 {
                        Text("Recommended: System Settings → Keyboard → “Press 🌐 key to” → **Do Nothing**, so the emoji picker doesn't pop up.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button(allDone ? "Start dictating" : "Finish later") {
                    settings.data.hasCompletedOnboarding = true
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 500)
        .onReceive(timer) { _ in
            mic = Permissions.microphoneGranted
            ax = Permissions.accessibilityGranted
            if ax, !DictationController.shared.hotkeys.isRunning { _ = DictationController.shared.startHotkeys() }
            if modelReady, !WhisperEngine.shared.isLoaded { DictationController.shared.preloadModel() }
        }
    }

    private var allDone: Bool { mic && ax && modelReady }

    @ViewBuilder
    private func step<Content: View>(_ n: Int, _ title: String, done: Bool, detail: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.25)).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                else { Text("\(n)").font(.caption.bold()) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if !done { action().controlSize(.small) }
            }
            Spacer()
        }
    }
}
