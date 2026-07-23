// Renders "3Wood" wordmark samples in the three candidate fonts.
// Run: swift design/render_wordmarks.swift
import AppKit

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func loadFont(_ path: String, size: CGFloat) -> NSFont {
    let url = URL(fileURLWithPath: path)
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
    return CTFontCreateWithFontDescriptor(descs[0], size, nil) as NSFont
}

let candidates: [(String, String, String)] = [
    ("1 · DM Serif Display", "design/fonts/DMSerifDisplay-Regular.ttf", "refined editorial serif — quiet clubhouse elegance"),
    ("2 · Graduate", "design/fonts/Graduate-Regular.ttf", "collegiate slab — varsity crest, sporty tradition"),
    ("3 · Abril Fatface", "design/fonts/AbrilFatface-Regular.ttf", "heavy display serif — bold poster statement"),
]

let W = 1200, H = 1050
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .calibratedRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

hex("#FFFFFF").setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
NSAttributedString(string: "3Wood — Wordmark Candidates",
                   attributes: [.font: NSFont.systemFont(ofSize: 36, weight: .bold),
                                .foregroundColor: hex("#111111")])
    .draw(at: NSPoint(x: 60, y: 970))

for (i, (name, path, mood)) in candidates.enumerated() {
    let top = CGFloat(900 - i * 300)
    NSAttributedString(string: name,
                       attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                                    .foregroundColor: hex("#111111")])
        .draw(at: NSPoint(x: 60, y: top))
    NSAttributedString(string: mood,
                       attributes: [.font: NSFont.systemFont(ofSize: 18),
                                    .foregroundColor: hex("#777777")])
        .draw(at: NSPoint(x: 60, y: top - 28))

    // sample card: cream background, dark pine wordmark, gold ball dotting the "3"
    let card = NSRect(x: 60, y: top - 220, width: 1080, height: 175)
    hex("#F7F3E8").setFill()
    NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()
    hex("#E3D9C2").setStroke()
    NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).stroke()
    let font = loadFont(path, size: 96)
    let mark = NSAttributedString(string: "3Wood",
                                  attributes: [.font: font, .foregroundColor: hex("#12301C")])
    let sz = mark.size()
    mark.draw(at: NSPoint(x: card.midX - sz.width / 2, y: card.midY - sz.height / 2))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "design/wordmark-candidates.png"))
print("wrote design/wordmark-candidates.png")
