import SwiftUI

struct ComparisonView: View {
    let newCourseName: String
    let newCourseLocation: String
    let candidate: RankedCourse
    let comparisonsRemaining: Int
    let onAnswer: (RankingEngine.Answer) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Which did you like more?")
                .font(.title3.bold())
                .padding(.top)

            comparisonCard(
                name: newCourseName,
                location: newCourseLocation,
                tag: "New"
            ) {
                onAnswer(.preferNew)
            }

            Text("vs")
                .font(.headline)
                .foregroundStyle(.secondary)

            comparisonCard(
                name: candidate.name,
                location: candidate.locationText,
                tag: nil
            ) {
                onAnswer(.preferExisting)
            }

            Spacer()

            Button("Too close to call") {
                onAnswer(.tooClose)
            }
            .font(.subheadline)

            Text(comparisonsRemaining == 1
                 ? "Last comparison"
                 : "At most \(comparisonsRemaining) comparisons left")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func comparisonCard(
        name: String, location: String, tag: String?, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let tag {
                    Text(tag.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.fairwayGreen.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.fairwayGreen)
                }
                Text(name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ComparisonView(
        newCourseName: "Chambers Bay",
        newCourseLocation: "University Place, WA",
        candidate: RankedCourse(
            courseID: 1, name: "Pebble Beach Golf Links", city: "Pebble Beach", state: "CA",
            bucket: .liked, rankPosition: 1, score: 8.4
        ),
        comparisonsRemaining: 3
    ) { _ in }
}
