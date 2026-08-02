import SwiftUI

/// One-step "add to Want to Play": pick a course, it's saved, done.
/// The ranking flow gets a full-screen cover because it's a multi-screen
/// interview; this is a single choice, so it's a sheet.
struct AddToWantToPlaySheet: View {
    /// Called after a successful save, before the sheet dismisses.
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ranked: [RankedCourse] = []
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            CoursePickerView(
                prompt: "Which course do you want to play?",
                emptyTitle: "Find a course to save",
                emptyMessage: "Search by name or city."
            ) { course in
                Task { await add(course) }
            }
            .creamScreen()
            .navigationTitle("Want to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Logging a course clears it from Want to Play server-side
            // (insert_ranking), so the app treats the two lists as exclusive.
            // Loading the played list up front keeps that true here.
            .task { ranked = (try? await RankingRepo.myRankedCourses()) ?? [] }
            .alert("Already played", isPresented: .init(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func add(_ course: Course) async {
        guard !isSaving else { return }
        if ranked.contains(where: { $0.courseID == course.id }) {
            message = "\(course.name) is already in your Played list, so it can't also be a course you want to play."
            return
        }
        isSaving = true
        do {
            try await WantToPlayRepo.add(courseID: course.id)
            onAdded()
            dismiss()
        } catch {
            message = "Couldn't save \(course.name). \(error.localizedDescription)"
        }
        isSaving = false
    }
}
