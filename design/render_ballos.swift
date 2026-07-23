// Refined "Ball O's" wordmark variants — balls type-integrated at the o slots.
// Run: swift design/render_ballos.swift
import AppKit

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let pine = hex("#12301C"), gold = hex("#D9A441")
let cream = hex("#F7F3E8"), sand = hex("#E3D9C2")

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let desc = base.fontDescriptor.withDesign(.rounded),
       let f = NSFont(descriptor: desc, size: size) { return f }
    return base
}

func serif(_ size: CGFloat) -> NSFont {
    let url = URL(fileURLWithPath: "design/fonts/DMSerifDisplay-Regular.ttf")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
    return CTFontCreateWithFontDescriptor(descs[0], size, nil) as NSFont
}

func width(_ s: String, _ font: NSFont) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: font]).size().width
}

func golfBall(center: NSPoint, r: CGFloat) {
    let circle = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                             width: 2 * r, height: 2 * r))
    NSColor.white.setFill(); circle.fill()
    hex("#CFC6AE").setStroke(); circle.lineWidth = max(1.5, r * 0.055); circle.stroke()
    hex("#D8D2BF").setFill()
    let d = r * 0.13
    for (dx, dy): (CGFloat, CGFloat) in [(-0.34, 0.26), (0.1, 0.4), (0.42, 0.12),
                                          (-0.12, -0.02), (0.3, -0.24), (-0.4, -0.18),
                                          (-0.04, -0.4)] {
        NSBezierPath(ovalIn: NSRect(x: center.x + dx * r - d / 2,
                                    y: center.y + dy * r - d / 2, width: d, height: d)).fill()
    }
}

// Draws the wordmark with the o's replaced by golf balls at their exact
// glyph slots; the second ball gets a small gold tee descender.
func ballWordmark(font: NSFont, at origin: NSPoint, teeSecond: Bool = true) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: pine]
    // slight extra tracking around the balls so they never touch
    let t = font.pointSize * 0.04
    NSAttributedString(string: "3W", attributes: attrs).draw(at: origin)
    let dX = origin.x + width("3Woo", font) + 2 * t
    NSAttributedString(string: "d", attributes: attrs).draw(at: NSPoint(x: dX, y: origin.y))

    // font.descender is negative: baseline sits at origin.y - descender
    let baseline = origin.y - font.descender
    let xh = font.xHeight
    let r = xh / 2
    let o1 = origin.x + width("3W", font) + (width("3Wo", font) - width("3W", font)) / 2
    let o2 = origin.x + width("3Wo", font) + (width("3Woo", font) - width("3Wo", font)) / 2 + t
    let cy = baseline + xh / 2

    golfBall(center: NSPoint(x: o1, y: cy), r: r)
    golfBall(center: NSPoint(x: o2, y: cy), r: r)

    if teeSecond {
        // tee as a small gold descender under the second ball
        gold.setFill()
        let t = NSBezierPath()
        let topY = cy - r + font.pointSize * 0.02
        let cup = font.pointSize * 0.10, stem = font.pointSize * 0.035
        t.move(to: NSPoint(x: o2 - cup, y: topY))
        t.line(to: NSPoint(x: o2 + cup, y: topY))
        t.line(to: NSPoint(x: o2 + stem, y: topY - font.pointSize * 0.10))
        t.line(to: NSPoint(x: o2 + stem, y: topY - font.pointSize * 0.19))
        t.line(to: NSPoint(x: o2 - stem, y: topY - font.pointSize * 0.19))
        t.line(to: NSPoint(x: o2 - stem, y: topY - font.pointSize * 0.10))
        t.close(); t.fill()
    }
}

let W = 1200, H = 1080
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .calibratedRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
NSAttributedString(string: "Ball O's — Refined Variants",
                   attributes: [.font: NSFont.systemFont(ofSize: 36, weight: .bold),
                                .foregroundColor: hex("#111111")])
    .draw(at: NSPoint(x: 60, y: 1000))

func card(_ i: Int, _ title: String, _ mood: String) -> NSRect {
    let top = CGFloat(930 - i * 310)
    NSAttributedString(string: title,
                       attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                                    .foregroundColor: hex("#111111")])
        .draw(at: NSPoint(x: 60, y: top))
    NSAttributedString(string: mood,
                       attributes: [.font: NSFont.systemFont(ofSize: 18),
                                    .foregroundColor: hex("#777777")])
        .draw(at: NSPoint(x: 60, y: top - 28))
    let r = NSRect(x: 60, y: top - 230, width: 1080, height: 185)
    cream.setFill(); NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).fill()
    sand.setStroke(); NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).stroke()
    return r
}

do {
    let r = card(0, "A · Rounded Bold", "friendly but not chunky — balls sized exactly to the o's")
    let f = rounded(110, .bold)
    let w = width("3Wood", f)
    ballWordmark(font: f, at: NSPoint(x: r.midX - w / 2, y: r.midY - f.capHeight / 2 + f.descender))
}
do {
    let r = card(1, "B · Rounded Semibold", "lighter still — more airline-lounge than sports-bar")
    let f = rounded(110, .semibold)
    let w = width("3Wood", f)
    ballWordmark(font: f, at: NSPoint(x: r.midX - w / 2, y: r.midY - f.capHeight / 2 + f.descender))
}
do {
    let r = card(2, "C · Serif", "DM Serif base with ball o's — clubhouse elegance + wit")
    let f = serif(116)
    let w = width("3Wood", f)
    ballWordmark(font: f, at: NSPoint(x: r.midX - w / 2, y: r.midY - f.capHeight / 2 + f.descender))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "design/ballos-variants.png"))
print("wrote design/ballos-variants.png")
