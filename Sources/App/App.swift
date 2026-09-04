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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private let pageHolder = PageHolder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMainMenu()
        setupStatusItem()

        let controller = DictationController.shared
        controller.preloadModel()
        let started = controller.startHotkeys()

        MoveToApplications.offerIfNeeded()

        // Always show the window on a normal launch (double-click). It's the app's face.
        let s = Settings.shared.data
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.eventID == kAEOpenApplication
            && NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin || !s.hasCompletedOnboarding || !started || !Permissions.microphoneGranted {
            var page: Page = .home
            if let i = CommandLine.arguments.firstIndex(of: "--page"), i + 1 < CommandLine.arguments.count,
               let p = Page(rawValue: CommandLine.arguments[i + 1]) { page = p }   // for screenshots/testing
            showMain(page: page)
        }
        Task { await OllamaManager.shared.prepareIfActive() }
        Updater.shared.startPeriodicChecks()
        if CommandLine.arguments.contains("--install-update") {   // for testing the self-updater
            Task { await Updater.shared.check(quiet: false); Updater.shared.installAvailable() }
        }

        // Re-arm the hotkey tap once Accessibility is granted (polls while not running).
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let c = DictationController.shared
            if !c.hotkeys.isRunning, Permissions.accessibilityGranted { _ = c.startHotkeys() }
            self.updateIcon()
        }
    }

    /// Double-clicking the app icon while it's already running brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain(page: pageHolder.page)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        OllamaManager.shared.stop()
        WhisperEngine.shared.unloadSync()
    }

    // MARK: main menu

    /// Without an Edit menu, Cmd+C / Cmd+V / Cmd+A do nothing in the app's own text boxes.
    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About talkatanormalvolumeflow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide talkatanormalvolumeflow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit talkatanormalvolumeflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        NSApp.mainMenu = main
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
        case .idle: title = "Ready · \(s.shortcut.displayName) (\(s.mode == .hold ? "hold" : "toggle"))"
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

        let ai = NSMenuItem(title: "AI Polish", action: #selector(toggleAI), keyEquivalent: "")
        ai.state = s.polishActive ? .on : .off
        ai.isEnabled = s.polishReady
        ai.target = self
        menu.addItem(ai)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open talkatanormalvolumeflow…", action: #selector(openMain), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "History…", action: #selector(openHistory), keyEquivalent: "h").target = self
        if !Permissions.accessibilityGranted || !Permissions.microphoneGranted {
            menu.addItem(withTitle: "⚠️ Finish Setup…", action: #selector(openMain), keyEquivalent: "").target = self
        }
        if let v = Updater.shared.availableVersion {
            menu.addItem(withTitle: "⬆️ Update to version \(v)…", action: #selector(openMain), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit talkatanormalvolumeflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func toggleDictation() { DictationController.shared.toggleFromMenu() }
    @objc private func toggleAI() {
        Settings.shared.data.ollamaEnabled.toggle()
        Settings.shared.data.polishSkipped = false
        if Settings.shared.data.polishActive { Task { await OllamaManager.shared.prepareIfActive() } } else { OllamaManager.shared.stop() }
    }
    @objc private func openMain() { showMain(page: .home) }
    @objc private func checkForUpdates() { showMain(page: .home); Task { await Updater.shared.check(quiet: false) } }
    @objc private func openHistory() { showMain(page: .history) }


    // MARK: window

    func showMain(page: Page) {
        pageHolder.page = page
        if mainWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: MainView(holder: pageHolder)))
            w.title = "talkatanormalvolumeflow"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 960, height: 680))
            w.center()
            w.setFrameAutosaveName("MainWindow")
            w.delegate = self
            mainWindow = w
        }
        // Show a Dock icon while the window is open so it behaves like a normal app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only when the window closes; the hotkey keeps working.
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Offers to move the app into /Applications when it was launched from a DMG or Downloads.
@MainActor
enum MoveToApplications {
    static func offerIfNeeded() {
        let url = Bundle.main.bundleURL
        let path = url.path
        guard path.hasSuffix(".app"),
              !path.hasPrefix("/Applications/"),
              !path.hasPrefix(NSHomeDirectory() + "/Applications/"),
              !path.contains("/.build/"), !path.contains("/dist/") else { return }   // dev builds
        if UserDefaults.standard.bool(forKey: "declinedMoveToApplications") { return }

        let alert = NSAlert()
        alert.messageText = "Move talkatanormalvolumeflow to your Applications folder?"
        alert.informativeText = "Apps work best from the Applications folder, and macOS remembers the permissions you grant. This just takes a second."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: "declinedMoveToApplications")
            return
        }
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(url.lastPathComponent)
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            // Copy (not move): reading our own bundle never triggers a folder-access prompt, deleting from Downloads would.
            try fm.copyItem(at: url, to: dest)
            // Relaunch from the new location.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", dest.path]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            let err = NSAlert()
            err.messageText = "Couldn't move the app"
            err.informativeText = "\(error.localizedDescription)\n\nYou can drag it into Applications yourself from Finder."
            err.runModal()
        }
    }
}
