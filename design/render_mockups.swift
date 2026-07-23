// Renders theme-palette and app-icon mockups as PNGs.
// Run: swift design/render_mockups.swift
import AppKit

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func canvas(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    return rep
}

func draw(on rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor,
          at p: NSPoint, centered: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: centered ? NSPoint(x: p.x - sz.width / 2, y: p.y) : p)
}

let dir = "design"

// ---------- 1. Palette sheet ----------
struct Palette { let name, mood: String; let colors: [(String, String)] }
let palettes = [
    Palette(name: "1 · REFINED CLASSIC", mood: "classic clubhouse — Augusta-style understatement",
            colors: [("Deep Fairway", "#1E5B33"), ("Dark Pine", "#12301C"), ("Sunrise Gold", "#D9A441"),
                     ("Cream", "#F7F3E8"), ("Sand", "#E3D9C2")]),
    Palette(name: "2 · MODERN FRESH", mood: "energetic, social — closest to Beli's vibe",
            colors: [("Vivid Green", "#17A34A"), ("Ink", "#1C1C1E"), ("Coral Pop", "#FF6B57"),
                     ("Off-White", "#FAFAF7"), ("Cool Gray", "#E5E7EB")]),
    Palette(name: "3 · DARK PREMIUM", mood: "members-only, dark-first, gold accents",
            colors: [("Night Green", "#0E2418"), ("Moss", "#2E5941"), ("Champagne", "#C9B37E"),
                     ("Charcoal", "#121412"), ("Stone", "#8A8F8A")]),
]

let sheet = canvas(1480, 1120)
draw(on: sheet) {
    hex("#FFFFFF").setFill(); NSRect(x: 0, y: 0, width: 1480, height: 1120).fill()
    text("3Wood — Theme Directions", 44, .bold, hex("#111111"), at: NSPoint(x: 60, y: 1030))
    for (i, p) in palettes.enumerated() {
        let top = 940 - CGFloat(i) * 320
        text(p.name, 30, .semibold, hex("#111111"), at: NSPoint(x: 60, y: top))
        text(p.mood, 20, .regular, hex("#777777"), at: NSPoint(x: 60, y: top - 32))
        for (j, (name, h)) in p.colors.enumerated() {
            let x = 60 + CGFloat(j) * 275
            let r = NSRect(x: x, y: top - 210, width: 245, height: 150)
            hex(h).setFill()
            NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
            hex("#DDDDDD").setStroke()
            NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).stroke()
            text(name, 19, .medium, hex("#333333"), at: NSPoint(x: x, y: top - 240))
            text(h, 17, .regular, hex("#999999"), at: NSPoint(x: x, y: top - 264))
        }
    }
}
savePNG(sheet, "\(dir)/theme-palettes.png")

// ---------- shared icon helpers ----------
let S: CGFloat = 1024
func iconBase(_ body: () -> Void) -> NSBitmapImageRep {
    let rep = canvas(Int(S), Int(S))
    draw(on: rep) {
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: S, height: S),
                     xRadius: 229, yRadius: 229).addClip()
        body()
    }
    return rep
}
func vGradient(_ topColor: NSColor, _ bottomColor: NSColor) {
    NSGradient(starting: topColor, ending: bottomColor)!
        .draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)
}

// ---------- 2. Icon: Monogram 3W ----------
let mono = iconBase {
    vGradient(hex("#1E5B33"), hex("#12301C"))
    text("3W", 400, .heavy, hex("#F7F3E8"), at: NSPoint(x: S / 2, y: 330), centered: true)
    // gold fairway-horizon swoosh under the lettermark
    let sw = NSBezierPath()
    sw.move(to: NSPoint(x: 220, y: 285))
    sw.curve(to: NSPoint(x: 804, y: 285),
             controlPoint1: NSPoint(x: 400, y: 215), controlPoint2: NSPoint(x: 624, y: 215))
    sw.lineWidth = 26; sw.lineCapStyle = .round
    hex("#D9A441").setStroke(); sw.stroke()
}
savePNG(mono, "\(dir)/icon-1-monogram.png")

// ---------- 3. Icon: Club mark ----------
let club = iconBase {
    vGradient(hex("#F7F3E8"), hex("#E3D9C2"))
    let green = hex("#1E5B33")
    // shaft
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 800, y: 880))
    shaft.line(to: NSPoint(x: 445, y: 330))
    shaft.lineWidth = 42; shaft.lineCapStyle = .round
    green.setStroke(); shaft.stroke()
    // 3-wood head: rounded teardrop silhouette
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 470, y: 350))
    head.curve(to: NSPoint(x: 230, y: 250),
               controlPoint1: NSPoint(x: 430, y: 400), controlPoint2: NSPoint(x: 250, y: 380))
    head.curve(to: NSPoint(x: 560, y: 200),
               controlPoint1: NSPoint(x: 215, y: 140), controlPoint2: NSPoint(x: 460, y: 130))
    head.curve(to: NSPoint(x: 470, y: 350),
               controlPoint1: NSPoint(x: 590, y: 250), controlPoint2: NSPoint(x: 520, y: 320))
    head.close()
    green.setFill(); head.fill()
    // gold accent: ball on a tee, top-left
    hex("#D9A441").setFill()
    NSBezierPath(ovalIn: NSRect(x: 236, y: 700, width: 92, height: 92)).fill()
}
savePNG(club, "\(dir)/icon-2-clubmark.png")

// ---------- 4. Icon: Fairway landscape ----------
let fairway = iconBase {
    vGradient(hex("#F7F3E8"), hex("#EFE6D0"))
    // mowing stripes
    let stripes = ["#2E7D46", "#1E5B33", "#2E7D46", "#1E5B33"]
    for (i, c) in stripes.enumerated() {
        let y = CGFloat(4 - i - 1) * 130
        hex(c).setFill()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: y))
        p.line(to: NSPoint(x: S, y: y + 45))
        p.line(to: NSPoint(x: S, y: y + 175))
        p.line(to: NSPoint(x: 0, y: y + 130))
        p.close(); p.fill()
    }
    // sun
    hex("#D9A441").setFill()
    NSBezierPath(ovalIn: NSRect(x: 140, y: 760, width: 170, height: 170)).fill()
    // pin
    hex("#12301C").setFill()
    NSRect(x: 660, y: 380, width: 22, height: 420).fill()
    let flag = NSBezierPath()
    flag.move(to: NSPoint(x: 682, y: 800))
    flag.line(to: NSPoint(x: 880, y: 735))
    flag.line(to: NSPoint(x: 682, y: 670))
    flag.close()
    hex("#C0392B").setFill(); flag.fill()
}
savePNG(fairway, "\(dir)/icon-3-fairway.png")
