import SwiftUI

struct RankResultView: View {
    let courseID: Int
    let courseName: String
    let score: Double
    let position: Int
    let bucket: Bucket
    let onDone: () -> Void

    @State private var isWritingReview = false
    @State private var hasReviewed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(courseName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            // Vintage scorecard flourish: the score set huge in the brand
            // face between hairline rules.
            VStack(spacing: 12) {
                rule
                Text(String(format: "%.1f", score))
                    .font(.custom("Righteous-Regular", fixedSize: 88))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                    .accessibilityLabel(String(format: "Score %.1f", score))
                rule
            }

            Text("#\(position) of your \"\(bucket.label)\" courses")
                .font(.subheadline.smallCaps())
                .foregroundStyle(Color.darkPine)

            Spacer()

            // Strike while the round is fresh — reviews mostly happen here.
            Button(hasReviewed ? "Review saved ✓" : "Write a review") {
                isWritingReview = true
            }
            .font(.subheadline.weight(.medium))
            .tint(Color.fairwayGreen)
            .disabled(hasReviewed)

            Button {
                onDone()
            } label: {
                Text("Done")
            }
            .buttonStyle(.primary)
        }
        .padding()
        .creamScreen()
        .sheet(isPresented: $isWritingReview) {
            WriteReviewSheet(courseID: courseID, existing: nil) {
                hasReviewed = true
            }
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.sand)
            .frame(height: 1)
            .padding(.horizontal, 48)
    }

    /// Same banding as ScoreBadge; the gold band uses brass so the huge
    /// numeral stays readable on cream.
    private var scoreColor: Color {
        switch score {
        case 6.7...: .fairwayGreen
        case 3.4..<6.7: .medalGold
        default: .clayRed
        }
    }
}

#Preview {
    RankResultView(courseID: 1, courseName: "Pebble Beach Golf Links", score: 8.4, position: 1, bucket: .liked) {}
}
