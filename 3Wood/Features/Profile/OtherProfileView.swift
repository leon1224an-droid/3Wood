import SwiftUI

/// Another user's profile: stats, follow button, and their ranked list.
struct OtherProfileView: View {
    @State var person: ProfileSummary
    @State private var stats: ProfileStats?
    @State private var ranked: [RankedCourse] = []

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.displayName ?? person.username)
                            .font(.title3.bold())
                        Text("@\(person.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let stats {
                            Text("\(stats.played) played · \(stats.followers) followers · \(stats.following) following")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    FollowButton(person: $person)
                }
                .padding(.vertical, 4)
            }

            Section("Their courses") {
                if ranked.isEmpty {
                    Text("No courses ranked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, course in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).lineLimit(1)
                                Text(course.locationText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ScoreBadge(score: course.score, compact: true)
                        }
                    }
                }
            }
        }
        .navigationTitle("@\(person.username)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let statsTask = SocialRepo.stats(of: person.id)
            async let rankedTask = SocialRepo.rankedCourses(of: person.id)
            stats = try? await statsTask
            ranked = (try? await rankedTask) ?? []
        }
    }
}
