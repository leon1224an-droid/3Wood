import SwiftUI
import CoreText

/// Registers bundled display fonts. Call once at launch — the project uses
/// a generated Info.plist, so fonts are registered at runtime instead of
/// via UIAppFonts.
enum BrandFonts {
    static func register() {
        guard let url = Bundle.main.url(forResource: "Righteous-Regular",
                                        withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// The "3Wood" wordmark: vintage flat logotype in Righteous with both o's
/// replaced by knockout golf balls. `size` is the font point size; the
/// balls are sized to the font's x-height and sit on the baseline.
struct Wordmark: View {
    var size: CGFloat = 34

    private var ballDiameter: CGFloat { size * 0.526 }  // Righteous x-height

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.03) {
            letters("3W")
            ball
            ball
            letters("d")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3Wood")
    }

    private func letters(_ s: String) -> Text {
        Text(s)
            .font(.custom("Righteous-Regular", fixedSize: size))
            .foregroundStyle(Color.fairwayGreen)
    }

    private var ball: some View {
        GolfBallShape()
            .fill(Color.fairwayGreen, style: FillStyle(eoFill: true))
            .clipShape(Circle())
            .frame(width: ballDiameter, height: ballDiameter)
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
    }
}

/// Solid disc with a dimple lattice knocked out via even-odd fill;
/// edge dimples are clipped by the disc (pair with `.clipShape(Circle())`).
struct GolfBallShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        let step = r * 0.38, dot = r * 0.10
        for i in -3...3 {
            let y = CGFloat(i) * step
            let offset = (i % 2 == 0) ? 0 : step / 2
            for j in -3...3 {
                let x = CGFloat(j) * step + offset
                guard x * x + y * y < (r + dot) * (r + dot) else { continue }
                p.addEllipse(in: CGRect(x: c.x + x - dot, y: c.y + y - dot,
                                        width: 2 * dot, height: 2 * dot))
            }
        }
        return p
    }
}

#Preview {
    VStack(spacing: 24) {
        Wordmark(size: 22)
        Wordmark(size: 34)
        Wordmark(size: 48)
    }
    .padding()
}
