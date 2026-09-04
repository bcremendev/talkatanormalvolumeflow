import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static var delegate: AppDelegate?
    @MainActor static func main() {
        if DebugCLI.runIfRequested() { exit(0) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var settingsTab = SettingsTabHolder()
    private var observers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusItem()

        let controller = DictationController.shared
        controller.preloadModel()
        let started = controller.startHotkeys()

        let s = Settings.shared.data
        if !s.hasCompletedOnboarding || !started || !Permissions.microphoneGranted {
            showOnboarding()
        }
        if s.ollamaEnabled { Task { await OllamaManager.shared.ensureRunning() } }

        // Re-arm the hotkey tap once Accessibility is granted (polls while not running).
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let c = DictationController.shared
            if !c.hotkeys.isRunning, Permissions.accessibilityGranted { _ = c.startHotkeys() }
            self.updateIcon()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        OllamaManager.shared.stop()
        WhisperEngine.shared.unloadSync()
    }

    // MARK: status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictation")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    private func updateIcon() {
        let c = DictationController.shared
        let name: String
        switch c.state {
        case .idle, .notice: name = "mic"
        case .recording: name = "mic.fill"
        case .processing: name = "ellipsis.circle"
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Dictation")
        if case .recording = c.state {
            statusItem.button?.image = img?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            statusItem.button?.image?.isTemplate = false
        } else {
            statusItem.button?.image = img
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let c = DictationController.shared
        let s = Settings.shared.data

        let title: String
        switch c.state {
        case .idle: title = "Ready · \(s.shortcut.name) (\(s.mode == .hold ? "hold" : "toggle"))"
        case .recording: title = "Listening…"
        case .processing(let m): title = m
        case .notice(let m): title = m
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let status = NSMenuItem(title: c.modelStatus, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(withTitle: c.isRecording ? "Stop & Transcribe" : "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "").target = self

        let modeMenu = NSMenu()
        for m in ActivationMode.allCases {
            let item = NSMenuItem(title: m.label, action: #selector(setMode(_:)), keyEquivalent: "")
            item.representedObject = m.rawValue
            item.state = s.mode == m ? .on : .off
            item.target = self
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Shortcut Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let ai = NSMenuItem(title: "AI Polish (Ollama)", action: #selector(toggleAI), keyEquivalent: "")
        ai.state = s.ollamaEnabled ? .on : .off
        ai.target = self
        menu.addItem(ai)

        menu.addItem(.separator())
        menu.addItem(withTitle: "History…", action: #selector(openHistory), keyEquivalent: "h").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        if !Permissions.accessibilityGranted || !Permissions.microphoneGranted {
            menu.addItem(withTitle: "⚠️ Fix Permissions…", action: #selector(openPermissions), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit talkatanormalvolumeflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func toggleDictation() { DictationController.shared.toggleFromMenu() }
    @objc private func setMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = ActivationMode(rawValue: raw) { Settings.shared.data.mode = m }
    }
    @objc private func toggleAI() {
        Settings.shared.data.ollamaEnabled.toggle()
        if Settings.shared.data.ollamaEnabled { Task { await OllamaManager.shared.ensureRunning() } } else { OllamaManager.shared.stop() }
    }
    @objc private func openHistory() { showSettings(tab: .history) }
    @objc private func openSettings() { showSettings(tab: .general) }
    @objc private func openPermissions() { showSettings(tab: .permissions) }

    // MARK: windows

    func showSettings(tab: SettingsTab) {
        settingsTab.tab = tab
        if settingsWindow == nil {
            let view = SettingsRoot(holder: settingsTab)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "talkatanormalvolumeflow Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView { [weak self] in self?.onboardingWindow?.close() }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Welcome"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsTabHolder: ObservableObject { @Published var tab: SettingsTab = .general }

struct SettingsRoot: View {
    @ObservedObject var holder: SettingsTabHolder
    var body: some View { SettingsView(tab: $holder.tab) }
}
