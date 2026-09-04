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

/// A global shortcut. Either a lone modifier key (Fn, Right Option...) or a regular key plus modifiers.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64      // CGEventFlags raw value (only meaningful when !isModifierKey)
    var isModifierKey: Bool
    var name: String

    static let fn           = Shortcut(keyCode: 63, modifiers: 0, isModifierKey: true, name: "Fn / Globe 🌐")
    static let rightOption  = Shortcut(keyCode: 61, modifiers: 0, isModifierKey: true, name: "Right ⌥ Option")
    static let rightCommand = Shortcut(keyCode: 54, modifiers: 0, isModifierKey: true, name: "Right ⌘ Command")
    static let rightControl = Shortcut(keyCode: 62, modifiers: 0, isModifierKey: true, name: "Right ⌃ Control")
    static let presets: [Shortcut] = [fn, rightOption, rightCommand, rightControl]

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
    var showOverlay: Bool = true
    var playSounds: Bool = true
    var trailingSpace: Bool = true
    var restoreClipboard: Bool = true
    var insertMethod: InsertMethod = .paste

    var modelId: String = "small.en"
    var language: String = "en"          // "auto" or ISO code

    var removeFillers: Bool = true
    var fillerWords: [String] = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm", "mm", "ah"]
    var voiceCommands: Bool = true
    var smartCapitalization: Bool = true
    var replacements: [Replacement] = []

    var ollamaEnabled: Bool = false
    var ollamaModel: String = "qwen2.5:3b"
    var ollamaStyle: String = "Keep the speaker's voice. Only fix grammar, punctuation, remove filler words, and apply spoken self-corrections."

    var hasCompletedOnboarding: Bool = false
    var historyEnabled: Bool = true
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
