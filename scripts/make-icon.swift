// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's icon grid: an 824 pt body centred on a 1024 pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSShadow().then {
        $0.shadowBlurRadius = 20; $0.shadowOffset = NSSize(width: 0, height: -10);
        $0.shadowColor = .black.withAlphaComponent(0.3); $0.set()
    }
    NSGradient(colors: [NSColor(white: 0.24, alpha: 1), NSColor(white: 0.09, alpha: 1)])!.draw(in: shape, angle: -90)
    NSShadow().set()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // A history graph rising to the right, drawn as the menu bar draws it.
    let values: [CGFloat] = [0.18, 0.22, 0.2, 0.3, 0.26, 0.38, 0.33, 0.47, 0.42, 0.58, 0.5, 0.66, 0.6, 0.74]
    let graph = NSRect(x: 190, y: 250, width: 644, height: 420)
    let column = graph.width / CGFloat(values.count)
    for (i, v) in values.enumerated() {
        let rect = NSRect(
            x: graph.minX + CGFloat(i) * column + 6, y: graph.minY, width: column - 12, height: graph.height * v)
        NSColor.white.withAlphaComponent(0.35 + 0.65 * CGFloat(i) / CGFloat(values.count - 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
    }
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(rect: NSRect(x: 190, y: 220, width: 644, height: 6)).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSShadow { func then(_ f: (NSShadow) -> Void) { f(self) } }

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
if FileManager.default.fileExists(atPath: iconset.path) { try FileManager.default.removeItem(at: iconset) }
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
