import SwiftUI

/// Beli-style score chip: green for liked-range scores, gold for mid,
/// red for low, gray when unrated. Gold badges take dark ink — white
/// text fails WCAG on the light gold fill.
struct ScoreBadge: View {
    let score: Double?
    var compact = false

    var body: some View {
        Text(score.map { String(format: "%.1f", $0) } ?? "–")
            .font(.system(compact ? .caption2 : .subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(isGoldBand ? Color.inkOnGold : .white)
            .frame(minWidth: compact ? 26 : 34)
            .padding(.horizontal, compact ? 5 : 8)
            .padding(.vertical, compact ? 3 : 5)
            .background(color, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(score.map { String(format: "Score %.1f", $0) } ?? "Not rated")
    }

    private var isGoldBand: Bool {
        guard let score else { return false }
        return (3.4..<6.7).contains(score)
    }

    private var color: Color {
        guard let score else { return .gray }
        switch score {
        case 6.7...: return .fairwayGreen
        case 3.4..<6.7: return .sunriseGold
        default: return .clayRed
        }
    }
}

#Preview {
    HStack {
        ScoreBadge(score: 9.2)
        ScoreBadge(score: 5.0)
        ScoreBadge(score: 1.3)
        ScoreBadge(score: nil)
        ScoreBadge(score: 8.0, compact: true)
    }
}
