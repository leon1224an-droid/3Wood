import SwiftUI

/// Another user's profile: stats, follow button, and their ranked list.
struct OtherProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State var person: ProfileSummary
    @State private var stats: ProfileStats?
    @State private var ranked: [RankedCourse] = []
    @State private var lists: [CustomList] = []
    @State private var isBlocked = false
    @State private var isReporting = false
    @State private var isConfirmingBlock = false
    @State private var moderationNote: String?

    /// True when this screen was reached for the signed-in user (e.g. your own
    /// row in someone's followers list) — hides follow/report/block for self.
    private var isMe: Bool {
        if case .signedIn(let profile) = session.state { return profile.id == person.id }
        return false
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.displayName ?? person.username)
                                .font(.title2.bold())
                            Text("@\(person.username)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !isMe {
                            FollowButton(person: $person)
                        }
                    }
                    // Buttons + router push (not NavigationLink) so the List
                    // doesn't bolt a chevron onto each chip.
                    HStack(spacing: 10) {
                        Button {
                            router.push(.people(userID: person.id, mode: .followers))
                        } label: {
                            FollowChip(count: stats?.followers, label: "Followers")
                        }
                        .buttonStyle(.plain)
                        Button {
                            router.push(.people(userID: person.id, mode: .following))
                        } label: {
                            FollowChip(count: stats?.following, label: "Following")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            Section("Their courses") {
                if ranked.isEmpty {
                    Text("No courses ranked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, course in
                        // Router push (not NavigationLink) so revisiting a
                        // course already in the chain pops back to it.
                        Button {
                            router.push(.courseID(course.courseID))
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 24, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name).lineLimit(2)
                                    Text(course.locationText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                ScoreBadge(score: course.score, compact: true)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listRowBackground(Color.clear)

            if !lists.isEmpty {
                Section("Their lists") {
                    ForEach(lists) { list in
                        Button {
                            router.push(.list(list))
                        } label: {
                            ListCardRow(list: list)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Color.sand)
        .creamScreen()
        .navigationTitle("@\(person.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isMe {
                    menuButton
                }
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
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var menuButton: some View {
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

    private func reload() async {
        async let statsTask = SocialRepo.stats(of: person.id)
        async let rankedTask = SocialRepo.rankedCourses(of: person.id)
        async let listsTask = ListsRepo.publicLists(of: person.id)
        async let followingTask = SocialRepo.isFollowing(person.id)
        async let blockedTask = ModerationRepo.isBlocked(userID: person.id)
        stats = try? await statsTask
        ranked = (try? await rankedTask) ?? []
        lists = (try? await listsTask) ?? []
        if let following = try? await followingTask {
            person.isFollowing = following
        }
        isBlocked = (try? await blockedTask) ?? false
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
