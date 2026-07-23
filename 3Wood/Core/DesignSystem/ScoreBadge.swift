import SwiftUI

/// Beli-style score chip: green for liked-range scores, amber for mid,
/// red for low, gray when unrated.
struct ScoreBadge: View {
    let score: Double?
    var compact = false

    var body: some View {
        Text(score.map { String(format: "%.1f", $0) } ?? "–")
            .font(.system(compact ? .caption2 : .subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: compact ? 26 : 34)
            .padding(.horizontal, compact ? 5 : 8)
            .padding(.vertical, compact ? 3 : 5)
            .background(color, in: Capsule())
    }

    private var color: Color {
        guard let score else { return .gray }
        switch score {
        case 6.7...: return .fairwayGreen
        case 3.4..<6.7: return .orange
        default: return .red
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
