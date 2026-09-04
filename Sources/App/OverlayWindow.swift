import AppKit
import SwiftUI

/// Small floating pill at the bottom of the screen showing recording / processing state.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private weak var controller: DictationController?

    func bind(controller: DictationController) { self.controller = controller }

    func show() {
        guard let controller else { return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: OverlayView(controller: controller, recorder: controller.recorder))
            panel = p
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 24))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            if panel?.alphaValue == 0 { panel?.orderOut(nil) }
        })
    }
}

struct OverlayView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var recorder: AudioRecorder

    var body: some View {
        HStack(spacing: 12) {
            switch controller.state {
            case .recording:
                Image(systemName: "mic.fill").foregroundStyle(Theme.violet).font(.system(size: 14, weight: .semibold))
                Waveform(level: recorder.level)
                    .frame(width: 96, height: 26)
                Text("Listening…")
                    .font(.system(size: 13, weight: .medium))
                Text("esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .processing(let msg):
                ProgressView().controlSize(.small).tint(Theme.violet)
                Text(msg).font(.system(size: 13, weight: .medium))
            case .notice(let msg):
                Image(systemName: "exclamationmark.circle")
                Text(msg).font(.system(size: 12, weight: .medium)).lineLimit(2)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.wave.opacity(0.8), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .frame(width: 320, height: 56)
    }
}

/// A flowing wave in the icon's colours (sky → violet → pink → peach). Louder speech = taller, faster ripples.
struct Waveform: View {
    var level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let amp = Double(min(1, max(0.08, level * 3.2)))
                let mid = size.height / 2
                // Three layered ribbons, like the icon's stacked wave, each slightly offset.
                let layers: [(phase: Double, scale: Double, width: Double, opacity: Double)] = [
                    (0.0, 1.0, 3.2, 1.0), (0.9, 0.7, 2.4, 0.6), (1.8, 0.45, 1.8, 0.4),
                ]
                for l in layers {
                    var path = Path()
                    let steps = 48
                    for i in 0...steps {
                        let x = size.width * Double(i) / Double(steps)
                        let u = Double(i) / Double(steps)
                        // Fade the wave in at the left and out at the right so it feels like it trails off.
                        let envelope = sin(u * .pi)
                        let y = mid + sin(u * 4.2 + t * 6.5 + l.phase) * (size.height * 0.48) * amp * l.scale * envelope
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let gradient = Gradient(colors: [Theme.sky, Theme.violet, Theme.pink, Theme.peach])
                    g.opacity = l.opacity
                    g.stroke(path, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                             style: StrokeStyle(lineWidth: l.width, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
