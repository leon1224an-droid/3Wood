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
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
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
                    Button("Delete review", role: .destructive) {
                        Task { await deleteReview() }
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
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
