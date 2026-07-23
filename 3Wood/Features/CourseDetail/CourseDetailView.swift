import SwiftUI
import MapKit

struct CourseDetailView: View {
    let course: Course

    @State private var myRanking: RankedCourse?
    @State private var isLoggingCourse = false
    @State private var isBookmarked = false
    @State private var friendScores: [FriendScore] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.title2.bold())
                    Text(course.locationText)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if let holes = course.holes {
                            Label("\(holes) holes", systemImage: "flag")
                        }
                        if let type = course.courseType {
                            Label(type.capitalized, systemImage: "building.columns")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                // Your score (once ranked)
                if let myRanking {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Your score")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("#\(myRanking.rankPosition) of your \"\(myRanking.bucket.label)\" courses")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        ScoreBadge(score: myRanking.score)
                    }
                    .padding()
                    .background(Color.fairwayGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                // Community rating card
                HStack {
                    VStack(alignment: .leading) {
                        Text("Community rating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if course.ratingCount > 0 {
                            Text("^[\(course.ratingCount) rating](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("No ratings yet — be the first!")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    ScoreBadge(score: course.avgScore)
                }
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                if !friendScores.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Friends' scores")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(friendScores) { friend in
                            HStack {
                                Text("@\(friend.username)")
                                Spacer()
                                ScoreBadge(score: friend.score, compact: true)
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    isLoggingCourse = true
                } label: {
                    Label(myRanking == nil ? "Log this course" : "Update my ranking",
                          systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.fairwayGreen)

                // Map snippet
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: course.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))) {
                    Marker(course.name, coordinate: course.coordinate)
                        .tint(Color.fairwayGreen)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            }
            .padding()
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await toggleBookmark() }
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .tint(Color.fairwayGreen)
            }
        }
        .fullScreenCover(isPresented: $isLoggingCourse, onDismiss: {
            Task { await reloadMyRanking() }
        }) {
            LogCourseFlow(course: course)
        }
        .task { await reloadMyRanking() }
    }

    private func reloadMyRanking() async {
        async let mineTask = RankingRepo.myRankedCourses()
        async let bookmarkTask = WantToPlayRepo.contains(courseID: course.id)
        async let friendsTask = SocialRepo.friendScores(courseID: course.id)
        myRanking = (try? await mineTask)?.first { $0.courseID == course.id }
        isBookmarked = (try? await bookmarkTask) ?? false
        friendScores = (try? await friendsTask) ?? []
    }

    private func toggleBookmark() async {
        do {
            if isBookmarked {
                try await WantToPlayRepo.remove(courseID: course.id)
            } else {
                try await WantToPlayRepo.add(courseID: course.id)
            }
            isBookmarked.toggle()
        } catch {
            // Leave the icon as-is; the next reload reflects reality.
        }
    }
}
