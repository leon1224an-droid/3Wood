// Vintage/retro flat "3Wood" wordmark — first "o" as a proper golf ball.
// Run: swift design/render_retro.swift
import AppKit

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let forest = hex("#2A7238"), cream = hex("#F7F3E8"), sand = hex("#E3D9C2")

func load(_ file: String, _ size: CGFloat) -> NSFont {
    let url = URL(fileURLWithPath: "design/fonts/\(file)")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
    return CTFontCreateWithFontDescriptor(descs[0], size, nil) as NSFont
}

func width(_ s: String, _ font: NSFont, _ tracking: CGFloat) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: font, .kern: tracking]).size().width
}

// Flat knockout golf ball: solid disc in the letter color with the
// dimples punched out — same visual weight as the letterforms.
func golfBall(center: NSPoint, r: CGFloat, ink: NSColor, paper: NSColor) {
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                width: 2 * r, height: 2 * r)).fill()
    // dimple lattice across the full face, clipped by the disc edge
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                width: 2 * r, height: 2 * r)).addClip()
    paper.setFill()
    let step = r * 0.38, dot = r * 0.10
    for i in -3...3 {
        let y = CGFloat(i) * step
        let offset = (i % 2 == 0) ? 0 : step / 2
        for j in -3...3 {
            let x = CGFloat(j) * step + offset
            guard x * x + y * y < (r + dot) * (r + dot) else { continue }
            NSBezierPath(ovalIn: NSRect(x: center.x + x - dot, y: center.y + y - dot,
                                        width: 2 * dot, height: 2 * dot)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

// "3W" + balls in both o slots + "d", flat single color, optional tracking.
func wordmark(font: NSFont, at origin: NSPoint, tracking: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] =
        [.font: font, .foregroundColor: forest, .kern: tracking]
    // small extra gap around the balls so their outlines never touch
    let gap = font.pointSize * 0.03
    NSAttributedString(string: "3W", attributes: attrs).draw(at: origin)
    let dX = origin.x + width("3Woo", font, tracking) + 2 * gap
    NSAttributedString(string: "d", attributes: attrs).draw(at: NSPoint(x: dX, y: origin.y))

    let baseline = origin.y - font.descender
    let xh = font.xHeight
    let oAdvance = width("3Wo", font, tracking) - width("3W", font, tracking) - tracking
    let o1 = origin.x + width("3W", font, tracking) + oAdvance / 2
    let o2 = origin.x + width("3Wo", font, tracking) + oAdvance / 2 + gap
    golfBall(center: NSPoint(x: o1, y: baseline + xh / 2), r: xh / 2, ink: forest, paper: cream)
    golfBall(center: NSPoint(x: o2, y: baseline + xh / 2), r: xh / 2, ink: forest, paper: cream)
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
NSAttributedString(string: "3Wood — Vintage Flat Wordmark",
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

let variants: [(String, String, String, CGFloat, CGFloat)] = [
    ("A · Righteous", "Righteous-Regular.ttf", "art-deco retro — clean geometric, 60s clubhouse sign", 108, 2),
    ("B · Alfa Slab One", "AlfaSlabOne-Regular.ttf", "vintage slab poster — old scorecard letterpress", 98, 1),
    ("C · Lilita One", "LilitaOne-Regular.ttf", "soft retro rounded — friendly 70s pro-shop decal", 108, 2),
]

for (i, (title, file, mood, size, tracking)) in variants.enumerated() {
    let r = card(i, title, mood)
    let f = load(file, size)
    let w = width("3Wood", f, tracking)
    wordmark(font: f, at: NSPoint(x: r.midX - w / 2, y: r.midY - f.capHeight / 2 + f.descender),
             tracking: tracking)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "design/retro-wordmarks.png"))
print("wrote design/retro-wordmarks.png")
