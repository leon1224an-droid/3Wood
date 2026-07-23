// Renders the final 3Wood club-mark app icon (light / dark / tinted)
// as full-bleed 1024x1024 PNGs into AppIcon.appiconset.
// Run: swift design/render_appicon.swift
import AppKit

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let S: CGFloat = 1024

func render(_ path: String, bgTop: NSColor, bgBottom: NSColor, mark: NSColor, ball: NSColor) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: bgTop, ending: bgBottom)!
        .draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)

    // shaft — from top-right toward the head at lower-left
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 812, y: 872))
    shaft.line(to: NSPoint(x: 462, y: 340))
    shaft.lineWidth = 48
    shaft.lineCapStyle = .round
    mark.setStroke(); shaft.stroke()

    // 3-wood head: rounded teardrop silhouette
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 490, y: 362))
    head.curve(to: NSPoint(x: 226, y: 252),
               controlPoint1: NSPoint(x: 446, y: 418), controlPoint2: NSPoint(x: 248, y: 396))
    head.curve(to: NSPoint(x: 590, y: 198),
               controlPoint1: NSPoint(x: 208, y: 130), controlPoint2: NSPoint(x: 480, y: 122))
    head.curve(to: NSPoint(x: 490, y: 362),
               controlPoint1: NSPoint(x: 624, y: 254), controlPoint2: NSPoint(x: 544, y: 330))
    head.close()
    mark.setFill(); head.fill()

    // gold ball, upper-left — where the shot is headed
    ball.setFill()
    NSBezierPath(ovalIn: NSRect(x: 224, y: 700, width: 104, height: 104)).fill()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let set = "3Wood/Resources/Assets.xcassets/AppIcon.appiconset"
// light: green mark on warm cream
render("\(set)/AppIcon.png",
       bgTop: hex("#F7F3E8"), bgBottom: hex("#E3D9C2"),
       mark: hex("#1E5B33"), ball: hex("#D9A441"))
// dark: cream mark on deep pine
render("\(set)/AppIcon-Dark.png",
       bgTop: hex("#1E5B33"), bgBottom: hex("#12301C"),
       mark: hex("#F7F3E8"), ball: hex("#D9A441"))
// tinted: grayscale — system applies the tint
render("\(set)/AppIcon-Tinted.png",
       bgTop: hex("#3A3A3A"), bgBottom: hex("#1C1C1C"),
       mark: hex("#EDEDED"), ball: hex("#B8B8B8"))
