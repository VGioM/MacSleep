// Draws Resources/AppIcon.icns: a crescent moon over a night sky turning to dawn.
// Run with: swift tools/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Squircle background, deep night at the top warming into dawn at the bottom.
    let inset = 100 * s
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.42, alpha: 1),
                        NSColor(red: 0.45, green: 0.30, blue: 0.55, alpha: 1),
                        NSColor(red: 0.14, green: 0.14, blue: 0.36, alpha: 1),
                        NSColor(red: 0.05, green: 0.06, blue: 0.18, alpha: 1)],
               atLocations: [0, 0.28, 0.6, 1], colorSpace: .deviceRGB)!
        .draw(in: shape, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // A few stars in the dark half.
    NSColor(white: 1, alpha: 0.85).setFill()
    for (x, y, r) in [(250.0, 780.0, 9.0), (360, 870, 6), (300, 640, 5), (770, 360 + 470, 7), (460, 720, 4)] {
        NSBezierPath(ovalIn: NSRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)).fill()
    }

    // Crescent: the moon disc minus an offset disc.
    let c = NSPoint(x: 560 * s, y: 600 * s), r = 210 * s
    let moon = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    NSGraphicsContext.saveGraphicsState()
    let bite = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
    let o = NSPoint(x: c.x + 115 * s, y: c.y + 85 * s)
    bite.append(NSBezierPath(ovalIn: NSRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r)))
    bite.windingRule = .evenOdd
    bite.addClip()
    NSColor(red: 1.0, green: 0.95, blue: 0.80, alpha: 1).setFill()
    moon.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The sun about to rise along the bottom edge.
    let sun = NSPoint(x: size / 2, y: inset - 40 * s)
    let sr = 170 * s
    NSColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: sun.x - sr, y: sun.y - sr, width: 2 * sr, height: 2 * sr)).fill()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "iconutil a échoué")
