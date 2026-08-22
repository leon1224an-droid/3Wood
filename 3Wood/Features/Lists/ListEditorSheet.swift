import SwiftUI

/// Create a new list, or rename/edit an existing one — same form either way.
struct ListEditorSheet: View {
    /// Nil creates a new list; non-nil edits it in place.
    let editing: CustomList?
    let onSaved: (CustomList) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var visibility: CustomList.Visibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxTitleLength = 80
    private let maxDescriptionLength = 5000

    init(editing: CustomList?, onSaved: @escaping (CustomList) -> Void) {
        self.editing = editing
        self.onSaved = onSaved
        _title = State(initialValue: editing?.title ?? "")
        _description = State(initialValue: editing?.description ?? "")
        _visibility = State(initialValue: editing?.visibility ?? .private)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= maxTitleLength
            && description.count <= maxDescriptionLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("listTitleField")
                } footer: {
                    Text("\(trimmedTitle.count) / \(maxTitleLength)")
                }

                Section {
                    TextField("Add a note about this list (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Description")
                } footer: {
                    // Plain text now; the column exists so a richer editor can
                    // land later without a migration.
                    Text("Optional. \(description.count) / \(maxDescriptionLength)")
                }

                Section {
                    Picker("Visibility", selection: $visibility) {
                        Text("Private").tag(CustomList.Visibility.private)
                        Text("Public").tag(CustomList.Visibility.public)
                    }
                    // Default Picker style in a Form pushes to a separate
                    // screen, which buries the public/private choice enough
                    // that it's easy to never notice it's there. Segmented
                    // keeps it inline and visible at a glance.
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("listVisibilityPicker")
                } footer: {
                    Text(visibility == .public
                         ? "Anyone can find this in Explore and on your profile."
                         : "Only you can see this list.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Color.clayRed)
                    }
                }
            }
            .creamScreen()
            .navigationTitle(editing == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                        .accessibilityIdentifier("saveListButton")
                }
            }
        }
    }

    private func save() async {
        guard !ContentFilter.isObjectionable(trimmedTitle)
                && !ContentFilter.isObjectionable(description) else {
            errorMessage = "That contains language we don't allow. Please revise it."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let editing {
                try await ListsRepo.update(
                    listID: editing.id, title: trimmedTitle,
                    description: trimmedDescription, visibility: visibility
                )
                var updated = editing
                updated.title = trimmedTitle
                updated.description = trimmedDescription.isEmpty ? nil : trimmedDescription
                updated.visibility = visibility
                onSaved(updated)
            } else {
                let id = try await ListsRepo.create(
                    title: trimmedTitle,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    visibility: visibility
                )
                onSaved(CustomList(
                    id: id, title: trimmedTitle,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    visibility: visibility, ownerID: nil, ownerUsername: nil,
                    isMine: true, likedByMe: false, courseCount: 0, likeCount: 0,
                    commentCount: 0, createdAt: Date(), updatedAt: Date()
                ))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
