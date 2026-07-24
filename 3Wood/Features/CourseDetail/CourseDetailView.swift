import SwiftUI
import MapKit

struct CourseDetailView: View {
    let course: Course

    @State private var myRanking: RankedCourse?
    @State private var isLoggingCourse = false
    @State private var isBookmarked = false
    @State private var friendScores: [FriendScore] = []
    @State private var reviews: [Review] = []
    @State private var isWritingReview = false
    @State private var freshCourse: Course?
    @State private var isConfirmingRemoval = false
    @State private var actionError: String?

    private var myReview: Review? { reviews.first(where: \.isMine) }
    /// Community numbers refreshed after ranking; falls back to the passed-in
    /// snapshot so the screen never says "no ratings" over a fresh one.
    private var live: Course { freshCourse ?? course }

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
                        if live.ratingCount > 0 {
                            Text("^[\(live.ratingCount) rating](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("No ratings yet — be the first!")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    ScoreBadge(score: live.avgScore)
                }
                .padding()
                .card()

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
                }
                .buttonStyle(.primary)

                if myRanking != nil {
                    Button("Remove from my courses") {
                        isConfirmingRemoval = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.clayRed)
                    .frame(maxWidth: .infinity)
                }

                reviewsSection

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
        .creamScreen()
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
        .sheet(isPresented: $isWritingReview) {
            WriteReviewSheet(courseID: course.id, existing: myReview?.body) {
                Task { await reloadReviews() }
            }
        }
        .confirmationDialog(
            "Remove \(course.name)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from Played", role: .destructive) {
                Task { await removeRanking() }
            }
        } message: {
            Text("This removes it from your ranking and rescores the rest of the bucket.")
        }
        .alert("Something went wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task { await reloadMyRanking() }
    }

    @ViewBuilder
    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(reviews.isEmpty ? "Reviews" : "^[\(reviews.count) review](inflect: true)")
                    .font(.headline)
                Spacer()
                Button(myReview == nil ? "Write a review" : "Edit") {
                    isWritingReview = true
                }
                .font(.subheadline)
            }

            if reviews.isEmpty {
                Text("No reviews yet. Share what you thought of the course.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("@\(review.username)")
                                .font(.subheadline.weight(.semibold))
                            if review.isMine {
                                Text("You")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.fairwayGreen.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.fairwayGreen)
                            }
                            Spacer()
                            Text(review.createdAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(review.body)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .card()
                }
            }
        }
    }

    private func reloadMyRanking() async {
        async let mineTask = RankingRepo.myRankedCourses()
        async let bookmarkTask = WantToPlayRepo.contains(courseID: course.id)
        async let friendsTask = SocialRepo.friendScores(courseID: course.id)
        async let reviewsTask = ReviewRepo.reviews(courseID: course.id)
        async let courseTask = CourseRepo.course(id: course.id)
        myRanking = (try? await mineTask)?.first { $0.courseID == course.id }
        isBookmarked = (try? await bookmarkTask) ?? false
        friendScores = (try? await friendsTask) ?? []
        reviews = (try? await reviewsTask) ?? []
        freshCourse = (try? await courseTask) ?? freshCourse
    }

    private func removeRanking() async {
        do {
            try await RankingRepo.remove(courseID: course.id)
            await reloadMyRanking()
        } catch {
            actionError = "Couldn't remove this course. \(error.localizedDescription)"
        }
    }

    private func reloadReviews() async {
        reviews = (try? await ReviewRepo.reviews(courseID: course.id)) ?? reviews
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
            actionError = "Couldn't update Want to Play. \(error.localizedDescription)"
        }
    }
}
