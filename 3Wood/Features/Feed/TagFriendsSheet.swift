import SwiftUI

/// Pick the people you played with. Restricted to people you follow — the
/// server enforces the same rule, since letting anyone attach any stranger to
/// any round is a harassment vector.
struct TagFriendsSheet: View {
    let activityID: Int
    /// Usernames already tagged, so re-opening the sheet isn't a blank slate.
    let alreadyTagged: [String]
    let onSaved: ([String]) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [ProfileSummary] = []
    @State private var selected: Set<UUID> = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var actionError: String?

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    private var visible: [ProfileSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return friends }
        return friends.filter {
            $0.username.localizedCaseInsensitiveContains(trimmed)
                || ($0.displayName ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if loadFailed, friends.isEmpty {
                    LoadFailedView { await load() }
                } else if friends.isEmpty {
                    ContentUnavailableView(
                        "Nobody to tag yet",
                        systemImage: "person.2",
                        description: Text("You can tag people you follow. Find friends from your profile.")
                    )
                } else {
                    List(visible) { person in
                        // (empty-search state handled by the overlay below)
                        TagRow(person: person, isSelected: selected.contains(person.id)) {
                            if selected.contains(person.id) {
                                selected.remove(person.id)
                            } else {
                                selected.insert(person.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if visible.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                    .searchable(text: $query, prompt: "Search people you follow")
                    .keepsBackButtonDuringSearch()
                }
            }
            .creamScreen()
            .navigationTitle("Played with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Done") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .task { await load() }
            .alert("Couldn't save", isPresented: .init(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    /// Split out because the inline row body tipped the type-checker over its
    /// time budget.
    private struct TagRow: View {
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

    private func load() async {
        guard let myID else {
            // A missing session isn't "you follow nobody" — say so honestly.
            loadFailed = true
            isLoading = false
            return
        }
        do {
            friends = try await SocialRepo.following(of: myID)
            selected = Set(
                friends.filter { alreadyTagged.contains($0.username) }.map(\.id)
            )
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        do {
            try await ActivityRepo.setTags(activityID: activityID, userIDs: Array(selected))
            onSaved(friends.filter { selected.contains($0.id) }.map(\.username))
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
        isSaving = false
    }
}
