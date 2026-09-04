import Foundation
import Combine
import CoreGraphics

enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String { self == .hold ? "Hold to talk" : "Press to start / press to stop" }
}

enum InsertMethod: String, Codable, CaseIterable, Identifiable {
    case paste, type
    var id: String { rawValue }
    var label: String { self == .paste ? "Paste (fast, recommended)" : "Type keystrokes (slower, works everywhere)" }
}

/// A global shortcut. A lone modifier key (Fn, Right Option...), a regular key plus modifiers, or an extra mouse button.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64      // CGEventFlags raw value (only meaningful when !isModifierKey)
    var isModifierKey: Bool
    var name: String
    /// CGEvent button number for a mouse-button shortcut (2 = middle, 3 = back, 4 = forward, 5+ = extra buttons).
    /// Optional so settings saved before this field existed still decode.
    var mouseButton: Int? = nil

    var isMouseButton: Bool { mouseButton != nil }
    /// Human-readable name (modifier keys are always named from the key code, so old saved names can't go stale).
    var displayName: String {
        if let b = mouseButton { return Shortcut.mouseButtonName(b) }
        return isModifierKey ? KeyNames.name(for: keyCode) : name
    }
    /// SF Symbol for the "how to" illustration.
    var symbol: String { isMouseButton ? "computermouse.fill" : "hand.point.up.left.fill" }

    static let fn           = Shortcut(keyCode: 63, modifiers: 0, isModifierKey: true, name: "Fn / Globe 🌐")
    static let rightOption  = Shortcut(keyCode: 61, modifiers: 0, isModifierKey: true, name: "Right ⌥ Option")
    static let rightCommand = Shortcut(keyCode: 54, modifiers: 0, isModifierKey: true, name: "Right ⌘ Command")
    static let rightControl = Shortcut(keyCode: 62, modifiers: 0, isModifierKey: true, name: "Right ⌃ Control")
    static let presets: [Shortcut] = [fn, rightOption, rightCommand, rightControl]

    static func mouse(_ button: Int) -> Shortcut {
        Shortcut(keyCode: 0, modifiers: 0, isModifierKey: false, name: mouseButtonName(button), mouseButton: button)
    }
    static let mousePresets: [Shortcut] = [mouse(2), mouse(3), mouse(4)]
    static func mouseButtonName(_ b: Int) -> String {
        switch b {
        case 2: return "Middle mouse button"
        case 3: return "Mouse “back” button"
        case 4: return "Mouse “forward” button"
        default: return "Mouse button \(b + 1)"
        }
    }

    /// Which CGEventFlags bit a modifier keyCode toggles.
    static func flag(forModifierKeyCode code: UInt16) -> CGEventFlags? {
        switch code {
        case 63: return .maskSecondaryFn
        case 58, 61: return .maskAlternate
        case 55, 54: return .maskCommand
        case 59, 62: return .maskControl
        case 56, 60: return .maskShift
        default: return nil
        }
    }

    static func describe(keyCode: UInt16, flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        parts.append(KeyNames.name(for: keyCode))
        return parts.joined(separator: " ")
    }

    static let relevantFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]
}

enum KeyNames {
    static let map: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4",
        120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑", 114: "Help", 115: "Home", 116: "PgUp",
        117: "Fwd Delete", 119: "End", 121: "PgDn",
        54: "Right ⌘ Command", 55: "Left ⌘ Command", 56: "Left ⇧ Shift", 57: "Caps Lock", 58: "Left ⌥ Option",
        59: "Left ⌃ Control", 60: "Right ⇧ Shift", 61: "Right ⌥ Option", 62: "Right ⌃ Control", 63: "Fn / Globe 🌐",
    ]
    static func name(for code: UInt16) -> String { map[code] ?? "Key \(code)" }
}

struct Replacement: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

struct SettingsData: Codable, Equatable {
    var shortcut: Shortcut = .fn
    var mode: ActivationMode = .hold
    var launchAtLogin: Bool = false
    var playSounds: Bool = true
    var soundTheme: String = "chime"
    var trailingSpace: Bool = true

    var modelId: String = "small.en"
    var language: String = "en"          // "auto" or ISO code

    var removeFillers: Bool = true
    var fillerWords: [String] = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm", "mm", "ah"]
    var voiceCommands: Bool = true
    var replacements: [Replacement] = []

    /// AI polish is recommended and on unless the user turns it off (`polishSkipped`); it only runs once downloaded (`polishReady`).
    var ollamaModel: String = "qwen2.5:3b"
    var polishReady: Bool = false
    var polishSkipped: Bool = false
    var ollamaEnabled: Bool { get { !polishSkipped } set { polishSkipped = !newValue } }

    var hasCompletedOnboarding: Bool = false

    // Kept fixed (not user-facing) to keep the app simple.
    var smartCapitalization: Bool { true }
    var insertMethod: InsertMethod { .paste }
    var restoreClipboard: Bool { true }
    var showOverlay: Bool { true }
    var historyEnabled: Bool { true }
    var ollamaStyle: String { "Keep the speaker's voice. Only fix grammar and punctuation, remove filler words, and apply spoken self-corrections." }

    init() {}

    // Tolerant decoding: new fields get defaults instead of wiping the user's settings.
    private enum K: String, CodingKey {
        case shortcut, mode, launchAtLogin, playSounds, soundTheme, trailingSpace, modelId, language, removeFillers, fillerWords,
             voiceCommands, replacements, ollamaModel, polishReady, polishSkipped, hasCompletedOnboarding
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let d = SettingsData()
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? d.shortcut
        mode = try c.decodeIfPresent(ActivationMode.self, forKey: .mode) ?? d.mode
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        soundTheme = try c.decodeIfPresent(String.self, forKey: .soundTheme) ?? d.soundTheme
        trailingSpace = try c.decodeIfPresent(Bool.self, forKey: .trailingSpace) ?? d.trailingSpace
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? d.modelId
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        removeFillers = try c.decodeIfPresent(Bool.self, forKey: .removeFillers) ?? d.removeFillers
        fillerWords = try c.decodeIfPresent([String].self, forKey: .fillerWords) ?? d.fillerWords
        voiceCommands = try c.decodeIfPresent(Bool.self, forKey: .voiceCommands) ?? d.voiceCommands
        replacements = try c.decodeIfPresent([Replacement].self, forKey: .replacements) ?? d.replacements
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? d.ollamaModel
        polishReady = try c.decodeIfPresent(Bool.self, forKey: .polishReady) ?? d.polishReady
        polishSkipped = try c.decodeIfPresent(Bool.self, forKey: .polishSkipped) ?? d.polishSkipped
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(shortcut, forKey: .shortcut); try c.encode(mode, forKey: .mode)
        try c.encode(launchAtLogin, forKey: .launchAtLogin); try c.encode(playSounds, forKey: .playSounds)
        try c.encode(soundTheme, forKey: .soundTheme)
        try c.encode(trailingSpace, forKey: .trailingSpace); try c.encode(modelId, forKey: .modelId)
        try c.encode(language, forKey: .language); try c.encode(removeFillers, forKey: .removeFillers)
        try c.encode(fillerWords, forKey: .fillerWords); try c.encode(voiceCommands, forKey: .voiceCommands)
        try c.encode(replacements, forKey: .replacements)
        try c.encode(ollamaModel, forKey: .ollamaModel); try c.encode(polishReady, forKey: .polishReady)
        try c.encode(polishSkipped, forKey: .polishSkipped); try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }

    /// True when polish should actually run on a dictation.
    var polishActive: Bool { polishReady && !polishSkipped }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private static let key = "settings.v1"

    @Published var data: SettingsData {
        didSet { save() }
    }

    private init() {
        if let raw = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else {
            data = SettingsData()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.key)
        }
    }
}

enum AppPaths {
    static let appName = "talkatanormalvolumeflow"
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var models: URL {
        let d = support.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var ollama: URL {
        let d = support.appendingPathComponent("ollama", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var history: URL { support.appendingPathComponent("history.json") }
}
