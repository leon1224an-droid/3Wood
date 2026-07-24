import SwiftUI

struct WriteReviewSheet: View {
    let courseID: Int
    let existing: String?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var isSaving = false

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
                        .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear { body_ = existing ?? "" }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let text = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await ReviewRepo.upsert(courseID: courseID, body: text)
            onSaved()
            dismiss()
        } catch {
            // Keep the sheet open so the text isn't lost.
        }
    }

    private func deleteReview() async {
        do {
            try await ReviewRepo.delete(courseID: courseID)
            onSaved()
            dismiss()
        } catch {}
    }
}
