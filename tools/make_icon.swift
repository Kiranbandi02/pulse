// Generates Resources/AppIcon.icns — usage: swiftc tools/make_icon.swift -o /tmp/mkicon && /tmp/mkicon <outdir>
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1), NSColor(red: 0.05, green: 0.06, blue: 0.14, alpha: 1)])!
        .draw(in: bg, angle: -90)
    // pulse line
    let line = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(0.14, 0.50), (0.32, 0.50), (0.40, 0.72), (0.52, 0.28), (0.60, 0.58), (0.66, 0.50), (0.86, 0.50)]
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: s * p.0, y: s * p.1)
        i == 0 ? line.move(to: pt) : line.line(to: pt)
    }
    line.lineWidth = s * 0.055
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(red: 0.12, green: 0.85, blue: 0.7, alpha: 0.9)
    glow.shadowBlurRadius = s * 0.04
    glow.set()
    NSColor(red: 0.20, green: 0.92, blue: 0.75, alpha: 1).setStroke()
    line.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
