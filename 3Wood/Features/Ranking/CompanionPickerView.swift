import SwiftUI

/// "Who did you play with?" — asked between choosing a bucket and the
/// head-to-head comparisons, while the round is still what you're thinking
/// about. Solo is the one-tap path, so the common case costs nothing.
struct CompanionPickerView: View {
    let courseName: String
    let onDone: ([ProfileSummary]) -> Void

    @Environment(SessionStore.self) private var session
    @State private var friends: [ProfileSummary] = []
    @State private var selected: Set<UUID> = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Who did you play with?")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(courseName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            if isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if loadFailed, friends.isEmpty {
                LoadFailedView { await load() }
            } else if friends.isEmpty {
                ContentUnavailableView(
                    "No friends yet",
                    systemImage: "person.2",
                    description: Text("Follow people to tag them in your rounds.")
                )
            } else {
                List(friends) { person in
                    CompanionRow(person: person, isSelected: selected.contains(person.id)) {
                        if selected.contains(person.id) {
                            selected.remove(person.id)
                        } else {
                            selected.insert(person.id)
                        }
                    }
                }
                .listStyle(.plain)
            }

            VStack(spacing: 10) {
                Button {
                    onDone(friends.filter { selected.contains($0.id) })
                } label: {
                    Text(selected.isEmpty
                         ? "I played solo"
                         : "^[\(selected.count) playing partner](inflect: true)")
                }
                .buttonStyle(.primary)

                // "I played solo" was the only way forward, so anyone who
                // played with a non-user — or who follows nobody yet — had to
                // assert something false to continue.
                Button("Skip") { onDone([]) }
                    .font(.subheadline)
                    .tint(.secondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .creamScreen()
        .task { await load() }
    }

    private func load() async {
        guard let myID else { isLoading = false; return }
        do {
            friends = try await SocialRepo.following(of: myID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private struct CompanionRow: View {
        let person: ProfileSummary
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@" + person.username)
                            .foregroundStyle(.primary)
                        if let name = person.displayName {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.fairwayGreen : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.sand)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }
}
