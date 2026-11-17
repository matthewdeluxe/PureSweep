// Draws the app icon and writes an .iconset folder. build.sh turns it into AppIcon.icns with iconutil.
// Usage: swift tools/make-icon.swift <output.iconset>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 rounded square, centred.
    let inset = s * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.10, green: 0.62, blue: 0.95, alpha: 1), NSColor(red: 0.30, green: 0.28, blue: 0.86, alpha: 1)])!
        .draw(in: shape, angle: -60)

    // White sparkle glyph.
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: rect.width * 0.5, weight: .semibold)) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let w = rect.width * 0.56
        let h = w * symbol.size.height / symbol.size.width
        tinted.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
