import SwiftUI

struct WriteReviewSheet: View {
    let courseID: Int
    let existing: String?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var isSaving = false
    @State private var saveError: String?

    /// Matches the reviews table check constraint (1–2000 characters).
    private let maxLength = 2000
    private var trimmed: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $body_)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(8)
                    .card()
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("How were the conditions, layout, value, pace?")
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                if trimmed.count > maxLength - 200 {
                    Text("\(trimmed.count) / \(maxLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(trimmed.count > maxLength ? Color.clayRed : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }
                Spacer()
                if existing != nil {
                    Button("Delete review") {
                        Task { await deleteReview() }
                    }
                    .foregroundStyle(Color.clayRed)
                    .padding(.top, 8)
                }
            }
            .padding()
            .creamScreen()
            .navigationTitle(existing == nil ? "Write a review" : "Edit review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(trimmed.isEmpty || trimmed.count > maxLength || isSaving)
                }
            }
            .onAppear { body_ = existing ?? "" }
            .alert("Couldn't save review", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await ReviewRepo.upsert(courseID: courseID, body: trimmed)
            onSaved()
            dismiss()
        } catch {
            // Keep the sheet open so the text isn't lost.
            saveError = error.localizedDescription
        }
    }

    private func deleteReview() async {
        do {
            try await ReviewRepo.delete(courseID: courseID)
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
