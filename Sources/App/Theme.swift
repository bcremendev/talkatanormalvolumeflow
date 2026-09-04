import AppKit
import SwiftUI

/// Colours lifted from the app icon: violet mic, sky-blue and pink wave, peach corner.
/// The whole window is painted with them: a gradient canvas, frosted cards, gradient buttons and a coloured sidebar.
enum Theme {
    static let violet = Color(red: 0.44, green: 0.26, blue: 0.89)     // #7143E3 mic body
    static let indigo = Color(red: 0.24, green: 0.25, blue: 0.70)     // mic stand
    static let sky    = Color(red: 0.25, green: 0.70, blue: 0.98)
    static let pink   = Color(red: 0.97, green: 0.45, blue: 0.65)
    static let peach  = Color(red: 0.99, green: 0.68, blue: 0.40)

    /// Accent used for toggles, radios, checkboxes and selection.
    static let accent = violet

    /// The icon's diagonal wash, for hero surfaces.
    static let wash = LinearGradient(colors: [pink, violet, sky], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The wave's colours, for highlights, borders and buttons.
    static let wave = LinearGradient(colors: [sky, violet, pink, peach], startPoint: .leading, endPoint: .trailing)
    static let waveColors: [Color] = [sky, violet, pink, peach]

    // MARK: canvas (whole-window background)

    /// Deep, saturated version of the icon in dark mode; airy pastel version in light mode.
    static func canvasColors(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [Color(red: 0.30, green: 0.10, blue: 0.36), Color(red: 0.16, green: 0.12, blue: 0.42), Color(red: 0.06, green: 0.26, blue: 0.42)]
            : [Color(red: 1.00, green: 0.90, blue: 0.94), Color(red: 0.92, green: 0.89, blue: 1.00), Color(red: 0.86, green: 0.95, blue: 1.00)]
    }

    /// Fill for cards and the sidebar: translucent white on dark, translucent white on light too (it reads as frosted glass).
    static func glass(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.09) : .white.opacity(0.55) }
    static func glassStrong(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.14) : .white.opacity(0.8) }
    static func hairline(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.14) : .white.opacity(0.9) }
    /// Text-field background inside a card.
    static func well(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black.opacity(0.25) : .white.opacity(0.7) }
}

/// The gradient wash behind every page, with two soft colour blooms so it isn't a flat ramp.
struct CanvasBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LinearGradient(colors: Theme.canvasColors(scheme), startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                Circle().fill(Theme.pink.opacity(scheme == .dark ? 0.35 : 0.35)).blur(radius: 90)
                    .frame(width: g.size.width * 0.6).offset(x: g.size.width * 0.55, y: -g.size.height * 0.25)
                Circle().fill(Theme.sky.opacity(scheme == .dark ? 0.35 : 0.4)).blur(radius: 90)
                    .frame(width: g.size.width * 0.6).offset(x: -g.size.width * 0.15, y: g.size.height * 0.55)
                Circle().fill(Theme.peach.opacity(scheme == .dark ? 0.22 : 0.35)).blur(radius: 80)
                    .frame(width: g.size.width * 0.4).offset(x: g.size.width * 0.7, y: g.size.height * 0.7)
            }
        }
        .ignoresSafeArea()
    }
}

/// Frosted card with a faint gradient edge.
struct ThemedCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.glass(scheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline(scheme), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.wave.opacity(scheme == .dark ? 0.35 : 0.5), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 10, y: 4)
    }
}

extension View {
    func themedCard(padding: CGFloat = 16) -> some View { modifier(ThemedCard(padding: padding)) }
    /// Title text painted with the wave gradient.
    func gradientText() -> some View { foregroundStyle(Theme.wave) }
}

/// Primary button: gradient fill, white text, soft glow.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.wave, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.violet.opacity(0.35), radius: 6, y: 2)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Secondary button: frosted pill.
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? AnyShapeStyle(Theme.wave) : AnyShapeStyle(Theme.glassStrong(scheme)), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.white.opacity(0.3) : Theme.hairline(scheme), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { GradientButtonStyle() }
}
extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static func glass(selected: Bool) -> GlassButtonStyle { GlassButtonStyle(selected: selected) }
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
