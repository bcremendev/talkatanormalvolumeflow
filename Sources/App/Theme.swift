import AppKit
import SwiftUI

/// Colours lifted from the app icon: violet mic, sky-blue and pink wave, peach corner.
enum Theme {
    static let violet = Color(red: 0.44, green: 0.26, blue: 0.89)     // #7143E3 mic body
    static let indigo = Color(red: 0.24, green: 0.25, blue: 0.70)     // mic stand
    static let sky    = Color(red: 0.25, green: 0.70, blue: 0.98)
    static let pink   = Color(red: 0.97, green: 0.45, blue: 0.65)
    static let peach  = Color(red: 0.99, green: 0.68, blue: 0.40)

    /// Accent used for buttons, toggles, selection and the waveform.
    static let accent = violet

    /// The icon's diagonal wash, for hero surfaces.
    static let wash = LinearGradient(colors: [pink, violet, sky], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The wave's colours, for the "Hold → Talk → Let go" highlight and progress accents.
    static let wave = LinearGradient(colors: [sky, violet, pink, peach], startPoint: .leading, endPoint: .trailing)
}

/// Menu bar icon drawn to match the app icon: a small mic with a wave trailing off to the right.
/// Template images so macOS tints them for light/dark menu bars; the recording variant is coloured.
enum MenuBarIcon {
    enum Style { case idle, recording, processing }

    static func image(_ style: Style) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        // Geometry (y up): capsule mic on the left, a two-hump wave trailing to the right.
        let body = NSBezierPath(roundedRect: NSRect(x: 3, y: 8, width: 5, height: 8), xRadius: 2.5, yRadius: 2.5)
        let cradle = NSBezierPath()
        cradle.lineWidth = 1.5; cradle.lineCapStyle = .round
        cradle.appendArc(withCenter: NSPoint(x: 5.5, y: 10), radius: 4.2, startAngle: 180, endAngle: 360, clockwise: false)
        cradle.move(to: NSPoint(x: 5.5, y: 5.8)); cradle.line(to: NSPoint(x: 5.5, y: 3.2))
        cradle.move(to: NSPoint(x: 3.6, y: 2.6)); cradle.line(to: NSPoint(x: 7.4, y: 2.6))
        let hump1 = (NSPoint(x: 10.5, y: 9), NSPoint(x: 11.8, y: 13), NSPoint(x: 13.2, y: 13), NSPoint(x: 14.5, y: 9))
        let hump2 = (NSPoint(x: 14.5, y: 9), NSPoint(x: 15.8, y: 5), NSPoint(x: 17.7, y: 5), NSPoint(x: 19.5, y: 9.5))
        func wavePath(_ humps: [(NSPoint, NSPoint, NSPoint, NSPoint)]) -> NSBezierPath {
            let p = NSBezierPath(); p.lineWidth = 2; p.lineCapStyle = .round
            for (i, h) in humps.enumerated() { if i == 0 { p.move(to: h.0) }; p.curve(to: h.3, controlPoint1: h.1, controlPoint2: h.2) }
            return p
        }

        let img = NSImage(size: size, flipped: false) { _ in
            switch style {
            case .idle:
                NSColor.black.setFill(); NSColor.black.setStroke()
                body.fill(); cradle.stroke(); wavePath([hump1, hump2]).stroke()
            case .processing:
                NSColor.black.setFill(); NSColor.black.setStroke()
                body.fill(); cradle.stroke()
                NSColor.black.withAlphaComponent(0.35).setStroke(); wavePath([hump1, hump2]).stroke()
            case .recording:
                NSColor(Theme.violet).setFill(); body.fill()
                NSColor(Theme.indigo).setStroke(); cradle.stroke()
                NSColor(Theme.sky).setStroke(); wavePath([hump1]).stroke()
                NSColor(Theme.pink).setStroke(); wavePath([hump2]).stroke()
            }
            return true
        }
        img.isTemplate = style != .recording
        return img
    }
}
