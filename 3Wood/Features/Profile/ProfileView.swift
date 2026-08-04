import SwiftUI
import Supabase

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigation.self) private var nav
    @State private var stats: ProfileStats?
    @State private var weekStreak: Int?
    @State private var wantToPlayCount: Int?
    @State private var myPhone: String?
    @State private var isEditingPhone = false
    @State private var isEditingUsername = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var myProfile: Profile? {
        if case .signedIn(let profile) = session.state { return profile }
        return nil
    }

    private var myID: UUID? { myProfile?.id }

    var body: some View {
        @Bindable var router = nav.profileRouter
        NavigationStack(path: $router.path) {
            List {
                if case .signedIn(let profile) = session.state {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? profile.username)
                                    .font(.title2.bold())
                                HStack(spacing: 8) {
                                    Text("@\(profile.username)")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let weekStreak, weekStreak > 0 {
                                        StreakBadge(weeks: weekStreak)
                                    }
                                }
                            }
                            // Buttons + router push (not NavigationLink) so
                            // the List doesn't bolt a chevron onto each chip.
                            HStack(spacing: 10) {
                                Button {
                                    nav.profileRouter.push(.people(userID: profile.id, mode: .followers))
                                } label: {
                                    FollowChip(count: stats?.followers, label: "Followers")
                                }
                                .buttonStyle(.plain)
                                Button {
                                    nav.profileRouter.push(.people(userID: profile.id, mode: .following))
                                } label: {
                                    FollowChip(count: stats?.following, label: "Following")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    listLink("Courses played", count: stats?.played, segment: .played)
                    listLink("Want to play", count: wantToPlayCount, segment: .wantToPlay)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink(value: Destination.findFriends) {
                        Label("Find friends", systemImage: "person.badge.plus")
                    }
                    Button {
                        isEditingUsername = true
                    } label: {
                        HStack {
                            Label("Change username", systemImage: "pencil")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        isEditingPhone = true
                    } label: {
                        HStack {
                            // The "why" sits on the row itself — as a section
                            // footer it was three rows adrift from the control
                            // it described, and read as boilerplate. The full
                            // explanation still lives in PhoneLinkSheet.
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Phone number")
                                    Text("Lets friends find you by number")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "phone")
                            }
                            .foregroundStyle(.primary)
                            Spacer()
                            Text(myPhone.map(PhoneNumber.display) ?? "Add")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: Destination.about) {
                        Label("About", systemImage: "info.circle")
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    Button("Sign out") {
                        Task { await session.signOut() }
                    }
                    .foregroundStyle(Color.clayRed)
                    Button("Delete account") {
                        isConfirmingDelete = true
                    }
                    .foregroundStyle(Color.clayRed)
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Color.sand)
            .creamScreen()
            .navigationTitle("Profile")
            // Counts go stale while the tab stays mounted — reload whenever the
            // screen comes back into view (tab switch or popping a child).
            .onAppear { Task { await reloadCounts() } }
            .refreshable { await reloadCounts() }
            .appDestinations()
            .sheet(isPresented: $isEditingPhone) {
                PhoneLinkSheet(existing: myPhone) { myPhone = $0 }
            }
            .sheet(isPresented: $isEditingUsername) {
                if let myProfile {
                    EditUsernameSheet(profile: myProfile)
                }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently removes your profile, rankings, and lists. It cannot be undone.")
            }
            .alert("Couldn't delete account", isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
        .environment(router)
    }

    /// Row that jumps to the Lists tab on the given segment.
    private func listLink(_ title: String, count: Int?, segment: ListsView.Segment) -> some View {
        Button {
            nav.showLists(segment)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reloadCounts() async {
        guard let myID else { return }
        stats = try? await SocialRepo.stats(of: myID)
        weekStreak = try? await FeedRepo.weekStreak()
        wantToPlayCount = (try? await WantToPlayRepo.list())?.count
        myPhone = try? await PhoneRepo.myPhone()
    }

    private func deleteAccount() async {
        do {
            try await supa.rpc("delete_account").execute()
            try? await supa.auth.signOut(scope: .local)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

/// Inline streak marker, sitting on the @username line.
///
/// Deliberately *not* shaped like FollowChip: those capsules are buttons, and
/// borrowing their outline made a read-only stat look tappable. This is plain
/// tinted text — gold is the design system's award colour — so it reads as a
/// property of the person rather than a control.
///
/// Not drawn at all when the streak is zero; "0 weeks" is worse than silence.
struct StreakBadge: View {
    let weeks: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.caption2)
            // "4-week streak", not "4 weeks streak" — attributive, so the
            // noun stays singular however many weeks it is.
            Text("\(weeks)-week streak")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        // medalGold, not sunriseGold: the lighter gold is ~2:1 on cream, so a
        // highlight ended up less readable than the secondary text beside it.
        // RankResultView made the same call for the big numeral.
        .foregroundStyle(Color.medalGold)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("^[\(weeks) week](inflect: true) streak of adding courses")
    }
}
