// Generates Resources/dmg-background.png (660x400 @2x). Run: swift scripts/make-dmg-background.swift
import AppKit

let w: CGFloat = 660, h: CGFloat = 400, scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Soft version of the app icon's pink → violet → sky wash.
NSGradient(colors: [NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.99, alpha: 1),
                    NSColor(calibratedRed: 0.90, green: 0.96, blue: 1.0, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -35)

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (w - sz.width) / 2, y: y))
}
text("Install talkatanormalvolumeflow", size: 22, weight: .bold, color: NSColor(calibratedWhite: 0.15, alpha: 1), y: h - 60)
text("Drag the app onto the Applications folder, then open it from Applications.", size: 13, weight: .regular, color: NSColor(calibratedWhite: 0.4, alpha: 1), y: h - 84)

// Arrow between the icon slots (icons at x=165 and x=495, y centered ~190)
let arrow = NSBezierPath()
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 265, y: 205)); arrow.line(to: NSPoint(x: 395, y: 205))
arrow.move(to: NSPoint(x: 370, y: 230)); arrow.line(to: NSPoint(x: 395, y: 205)); arrow.line(to: NSPoint(x: 370, y: 180))
NSColor(calibratedRed: 0.44, green: 0.26, blue: 0.89, alpha: 1).setStroke()
arrow.stroke()

NSAttributedString(string: "Step 1: drag the app →", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)]).draw(at: NSPoint(x: 100, y: 92))
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)]
NSAttributedString(string: "Step 2: open from Applications", attributes: attrs).draw(at: NSPoint(x: 400, y: 92))

text("Apple Silicon Mac · macOS 14 or newer · free and private", size: 11, weight: .regular, color: NSColor(calibratedWhite: 0.55, alpha: 1), y: 22)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/dmg-background.png"))
print("background written")
