// Generates Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
    let path = NSBezierPath(roundedRect: inset, xRadius: size * 0.22, yRadius: size * 0.22)
    let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.95, alpha: 1),
                                       NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.85, alpha: 1)])!
    gradient.draw(in: path, angle: -60)

    // Sound wave bars behind the mic
    NSColor.white.withAlphaComponent(0.22).setFill()
    let bars: [CGFloat] = [0.18, 0.32, 0.5, 0.32, 0.18]
    let barW = size * 0.055
    let gap = size * 0.03
    let totalW = CGFloat(bars.count) * barW + CGFloat(bars.count - 1) * gap
    var x = (size - totalW) / 2
    for h in bars {
        let bh = size * h
        NSBezierPath(roundedRect: NSRect(x: x, y: (size - bh) / 2, width: barW, height: bh), xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }

    // Mic glyph
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: mic.size)
        tinted.lockFocus()
        NSColor.white.set()
        mic.draw(in: NSRect(origin: .zero, size: mic.size))
        NSRect(origin: .zero, size: mic.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let s = mic.size
        tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    img.unlockFocus()
    return img
}

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = render(size: CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("iconset written")
