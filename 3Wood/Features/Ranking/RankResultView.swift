import SwiftUI

struct RankResultView: View {
    let courseName: String
    let score: Double
    let position: Int
    let bucket: Bucket
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(courseName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            ScoreBadge(score: score)
                .scaleEffect(2.2)
                .padding(.vertical, 20)

            Text("#\(position) of your \"\(bucket.label)\" courses")
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onDone()
            } label: {
                Text("Done")
            }
            .buttonStyle(.primary)
        }
        .padding()
        .creamScreen()
    }
}

#Preview {
    RankResultView(courseName: "Pebble Beach Golf Links", score: 8.4, position: 1, bucket: .liked) {}
}
