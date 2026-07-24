import SwiftUI

// "Refined Classic" surfaces: warm cream screens with hairline-ruled cards,
// like a paper scorecard. Everything stays flat — fills and 1px strokes only.

extension View {
    /// Warm cream page background for a whole screen. For scroll containers
    /// (List, Form, ScrollView) also hides the default system background.
    func creamScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cream)
    }

    /// A flat card: cream fill delineated by a 1px sand rule.
    func card(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.cream, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.sand, lineWidth: 1)
            )
    }
}

extension Color {
    /// Ink for text sitting on gold fills — fixed across modes because the
    /// gold fill stays light in both (white text fails WCAG on it).
    static let inkOnGold = Color(red: 0x12 / 255, green: 0x30 / 255, blue: 0x1C / 255)
}
