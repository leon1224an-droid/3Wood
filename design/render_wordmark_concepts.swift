// Renders three creative golf-themed "3Wood" wordmark concepts.
// Run: swift design/render_wordmark_concepts.swift
import AppKit

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let pine = hex("#12301C"), gold = hex("#D9A441"), green = hex("#1E5B33")
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

func run(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    a.draw(at: p)
    return a.size().width
}

func golfBall(center: NSPoint, r: CGFloat, fill: NSColor, dimple: NSColor) {
    let circle = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    fill.setFill(); circle.fill()
    hex("#C9BFA6").setStroke(); circle.lineWidth = max(2, r * 0.07); circle.stroke()
    dimple.setFill()
    let d = r * 0.16
    for (dx, dy): (CGFloat, CGFloat) in [(-0.38, 0.3), (0.05, 0.42), (0.44, 0.22),
                                          (-0.2, -0.05), (0.22, -0.12), (-0.44, -0.28),
                                          (0.0, -0.42), (0.4, -0.38)] {
        NSBezierPath(ovalIn: NSRect(x: center.x + dx * r - d / 2,
                                    y: center.y + dy * r - d / 2, width: d, height: d)).fill()
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
_ = run("3Wood — Golf Wordmark Concepts", NSFont.systemFont(ofSize: 36, weight: .bold),
        hex("#111111"), at: NSPoint(x: 60, y: 1000))

func card(_ i: Int, _ title: String, _ mood: String) -> NSRect {
    let top = CGFloat(930 - i * 310)
    _ = run(title, NSFont.systemFont(ofSize: 26, weight: .semibold), hex("#111111"),
            at: NSPoint(x: 60, y: top))
    _ = run(mood, NSFont.systemFont(ofSize: 18), hex("#777777"), at: NSPoint(x: 60, y: top - 28))
    let r = NSRect(x: 60, y: top - 230, width: 1080, height: 185)
    cream.setFill(); NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).fill()
    sand.setStroke(); NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).stroke()
    return r
}

// ── Concept 1: golf-ball o's, second ball teed up ──
do {
    let r = card(0, "1 · Ball O's", "the \"oo\" in Wood becomes two golf balls — one teed up")
    let font = rounded(104, .heavy)
    let baseline = r.midY - 40
    var x = r.minX + 200
    x += run("3W", font, pine, at: NSPoint(x: x, y: baseline)) + 8
    let ballR: CGFloat = 36
    // first ball on the baseline
    golfBall(center: NSPoint(x: x + ballR, y: baseline + 26 + ballR), r: ballR,
             fill: NSColor.white, dimple: sand)
    x += 2 * ballR + 22
    // second ball raised on a gold tee
    let c2 = NSPoint(x: x + ballR, y: baseline + 48 + ballR)
    golfBall(center: c2, r: ballR, fill: NSColor.white, dimple: sand)
    gold.setFill()
    let tee = NSBezierPath()
    tee.move(to: NSPoint(x: c2.x - 16, y: c2.y - ballR + 4))
    tee.line(to: NSPoint(x: c2.x + 16, y: c2.y - ballR + 4))
    tee.line(to: NSPoint(x: c2.x + 5, y: baseline + 34))
    tee.line(to: NSPoint(x: c2.x + 5, y: baseline + 24))
    tee.line(to: NSPoint(x: c2.x - 5, y: baseline + 24))
    tee.line(to: NSPoint(x: c2.x - 5, y: baseline + 34))
    tee.close(); tee.fill()
    x += 2 * ballR + 18
    _ = run("d", font, pine, at: NSPoint(x: x, y: baseline))
}

// ── Concept 2: the d's ascender is a flagstick ──
do {
    let r = card(1, "2 · Pin-Flag d", "the ascender of the \"d\" becomes the flagstick with a gold pennant")
    let font = serif(108)
    let baseline = r.midY - 52
    let x = r.minX + 300
    let w = run("3Wood", font, pine, at: NSPoint(x: x, y: baseline))
    // extend the d's stem upward and hang a pennant off it
    let stemX = x + w - 14
    pine.setFill()
    NSRect(x: stemX - 7, y: baseline + 100, width: 9, height: 66).fill()
    gold.setFill()
    let flag = NSBezierPath()
    flag.move(to: NSPoint(x: stemX + 2, y: baseline + 166))
    flag.line(to: NSPoint(x: stemX + 96, y: baseline + 141))
    flag.line(to: NSPoint(x: stemX + 2, y: baseline + 116))
    flag.close(); flag.fill()
}

// ── Concept 3: fairway underline swoosh with pin ──
do {
    let r = card(2, "3 · Fairway Underline", "clean wordmark over a fairway swoosh ending at the pin")
    let font = rounded(96, .bold)
    let baseline = r.midY - 24
    let x = r.minX + 290
    let w = run("3Wood", font, pine, at: NSPoint(x: x, y: baseline))
    // swoosh: gentle green arc under the word, gold ball at start,
    // pin planted past the end of the word
    let pinX = x + w + 34
    let sw = NSBezierPath()
    sw.move(to: NSPoint(x: x + 6, y: baseline - 18))
    sw.curve(to: NSPoint(x: pinX, y: baseline - 18),
             controlPoint1: NSPoint(x: x + w * 0.33, y: baseline - 48),
             controlPoint2: NSPoint(x: x + w * 0.72, y: baseline - 48))
    sw.lineWidth = 12; sw.lineCapStyle = .round
    green.setStroke(); sw.stroke()
    golfBall(center: NSPoint(x: x + 8, y: baseline - 18), r: 15, fill: NSColor.white, dimple: sand)
    pine.setFill()
    NSRect(x: pinX - 3, y: baseline - 20, width: 6, height: 78).fill()
    gold.setFill()
    let flag = NSBezierPath()
    flag.move(to: NSPoint(x: pinX + 3, y: baseline + 58))
    flag.line(to: NSPoint(x: pinX + 58, y: baseline + 44))
    flag.line(to: NSPoint(x: pinX + 3, y: baseline + 30))
    flag.close(); flag.fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "design/wordmark-concepts.png"))
print("wrote design/wordmark-concepts.png")
