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
                Waveform(level: recorder.level)
                    .frame(width: 90, height: 24)
                Text("Listening…")
                    .font(.system(size: 13, weight: .medium))
                Text("esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .processing(let msg):
                ProgressView().controlSize(.small)
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
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .frame(width: 320, height: 56)
    }
}

struct Waveform: View {
    var level: Float
    @State private var phase: Double = 0
    private let bars = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let wobble = 0.5 + 0.5 * sin(t * 9 + Double(i) * 0.9)
                    let h = 4 + CGFloat(Double(level) * 20 * (0.4 + wobble))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: max(4, min(24, h)))
                }
            }
        }
    }
}
