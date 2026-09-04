import AppKit
import CoreGraphics

/// What the user pressed while the shortcut recorder was armed.
enum RecordedInput {
    case key(code: UInt16, flags: CGEventFlags, isModifier: Bool)
    case mouseButton(Int)
}

/// Global hotkey via a CGEvent tap. Works with lone modifier keys (Fn, Right ⌥...), key combos and extra mouse buttons.
@MainActor
final class HotkeyManager {
    var shortcut: Shortcut = Settings.shared.data.shortcut
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Return true to swallow the Escape key.
    var onEscape: (() -> Bool)?
    /// When set, the next key or mouse-button press is reported here instead of acting.
    var recorder: ((RecordedInput) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isDown = false

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: hotkeyCallback, userInfo: refcon) else {
            return false
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isDown = false
    }

    /// Returns nil to swallow the event, or the event to pass it on.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        // Extra mouse buttons (middle, back, forward, thumb buttons on a Logitech MX Master etc.).
        if type == .otherMouseDown || type == .otherMouseUp {
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if type == .otherMouseDown, let rec = recorder {
                recorder = nil
                rec(.mouseButton(button))
                return nil
            }
            guard let wanted = shortcut.mouseButton, wanted == button else { return pass }
            if type == .otherMouseDown {
                if isDown { return nil }
                isDown = true; onPress?(); return nil
            }
            if isDown { isDown = false; onRelease?(); return nil }
            return pass
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection(Shortcut.relevantFlags)

        if type == .flagsChanged {
            guard let bit = Shortcut.flag(forModifierKeyCode: keyCode) else { return pass }
            let pressed = event.flags.contains(bit)
            if let rec = recorder {
                if pressed { recorder = nil; rec(.key(code: keyCode, flags: [], isModifier: true)) }
                return pass
            }
            guard shortcut.isModifierKey, keyCode == shortcut.keyCode else { return pass }
            if pressed, !isDown { isDown = true; onPress?() }
            else if !pressed, isDown { isDown = false; onRelease?() }
            // Swallow the Fn/Globe key so macOS doesn't also open the emoji picker or system dictation.
            return keyCode == 63 ? nil : pass
        }

        if type == .keyDown, let rec = recorder {
            recorder = nil
            rec(.key(code: keyCode, flags: flags, isModifier: false))
            return nil
        }

        if type == .keyDown, keyCode == 53, let onEscape, onEscape() { return nil }

        guard !shortcut.isModifierKey, !shortcut.isMouseButton, keyCode == shortcut.keyCode else { return pass }
        if type == .keyDown {
            let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isDown { return autorepeat ? nil : pass }
            guard flags == CGEventFlags(rawValue: shortcut.modifiers) else { return pass }
            isDown = true
            onPress?()
            return nil
        }
        if type == .keyUp, isDown {
            isDown = false
            onRelease?()
            return nil
        }
        return pass
    }
}

private func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    // The tap is installed on the main run loop, so this always runs on the main thread.
    return MainActor.assumeIsolated { manager.handle(type: type, event: event) }
}
