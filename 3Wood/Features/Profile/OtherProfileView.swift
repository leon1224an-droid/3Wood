import SwiftUI

/// Another user's profile: stats, follow button, and their ranked list.
struct OtherProfileView: View {
    @State var person: ProfileSummary
    @State private var stats: ProfileStats?
    @State private var ranked: [RankedCourse] = []
    @State private var isBlocked = false
    @State private var isReporting = false
    @State private var isConfirmingBlock = false
    @State private var moderationNote: String?

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
                    }
                    Spacer()
                    FollowButton(person: $person)
                }
                .padding(.vertical, 4)
                if let stats {
                    ProfileStatsBar(userID: person.id, stats: stats)
                        .padding(.vertical, 4)
                }
            }

            Section("Their courses") {
                if ranked.isEmpty {
                    Text("No courses ranked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, course in
                        NavigationLink(value: course) {
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
        }
        .creamScreen()
        .navigationTitle("@\(person.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Report user", systemImage: "flag") {
                        isReporting = true
                    }
                    if isBlocked {
                        Button("Unblock user", systemImage: "hand.raised.slash") {
                            Task { await setBlocked(false) }
                        }
                    } else {
                        Button("Block user", systemImage: "hand.raised", role: .destructive) {
                            isConfirmingBlock = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Report or block")
            }
        }
        .confirmationDialog("Report @\(person.username)?",
                            isPresented: $isReporting, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) {
                    Task { await report(reason) }
                }
            }
        } message: {
            Text("Reports are reviewed within 24 hours.")
        }
        .confirmationDialog("Block @\(person.username)?",
                            isPresented: $isConfirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { await setBlocked(true) }
            }
        } message: {
            Text("Their activity, reviews, and leaderboard entry are hidden from you.")
        }
        .alert("Thanks", isPresented: .init(
            get: { moderationNote != nil },
            set: { if !$0 { moderationNote = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moderationNote ?? "")
        }
        .navigationDestination(for: RankedCourse.self) { ranked in
            CourseDetailByID(courseID: ranked.courseID)
        }
        .task {
            async let statsTask = SocialRepo.stats(of: person.id)
            async let rankedTask = SocialRepo.rankedCourses(of: person.id)
            async let followingTask = SocialRepo.isFollowing(person.id)
            async let blockedTask = ModerationRepo.isBlocked(userID: person.id)
            stats = try? await statsTask
            ranked = (try? await rankedTask) ?? []
            if let following = try? await followingTask {
                person.isFollowing = following
            }
            isBlocked = (try? await blockedTask) ?? false
        }
    }

    private func report(_ reason: ReportReason) async {
        do {
            try await ModerationRepo.report(userID: person.id, reason: reason.rawValue)
            moderationNote = "Report received. We review reports within 24 hours."
        } catch {
            moderationNote = "Couldn't send the report. \(error.localizedDescription)"
        }
    }

    private func setBlocked(_ blocked: Bool) async {
        do {
            if blocked {
                try await ModerationRepo.block(userID: person.id)
                moderationNote = "@\(person.username) is blocked. Their content is hidden from you."
            } else {
                try await ModerationRepo.unblock(userID: person.id)
            }
            isBlocked = blocked
        } catch {
            moderationNote = "Couldn't update the block. \(error.localizedDescription)"
        }
    }
}

/// Canned report reasons keep the flow to two taps — no free-text screen.
enum ReportReason: String, CaseIterable, Identifiable {
    case offensive = "Offensive or abusive"
    case spam = "Spam or fake activity"
    case other = "Something else"

    var id: String { rawValue }
}
