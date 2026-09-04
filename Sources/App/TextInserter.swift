import AppKit
import Carbon.HIToolbox

/// Puts text into the frontmost app, via clipboard paste or synthesized keystrokes.
enum TextInserter {
    static func insert(_ text: String, method: InsertMethod, restoreClipboard: Bool) {
        switch method {
        case .paste: paste(text, restore: restoreClipboard)
        case .type: type(text)
        }
    }

    private static func paste(_ text: String, restore: Bool) {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = restore ? (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } : []
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChange = pb.changeCount

        sendKey(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        if restore {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // Only restore if nobody else has written to the clipboard since.
                guard pb.changeCount == ourChange else { return }
                pb.clearContents()
                if !saved.isEmpty { pb.writeObjects(saved) }
            }
        }
    }

    private static func type(_ text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        // Post in chunks; CGEvent unicode strings are limited in length.
        let chars = Array(text.utf16)
        var i = 0
        while i < chars.count {
            let chunk = Array(chars[i..<min(i + 20, chars.count)])
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                chunk.withUnsafeBufferPointer { buf in
                    down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                    up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            i += 20
            usleep(4000)
        }
    }

    static func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(8000)
        up?.post(tap: .cghidEventTap)
    }
}
