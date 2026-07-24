import SwiftUI

/// Loads a full Course by id, then shows CourseDetailView. Used where only a
/// course id is on hand (ranked-list rows, which carry RankedCourse).
struct CourseDetailByID: View {
    let courseID: Int
    @State private var course: Course?
    @State private var failed = false

    var body: some View {
        Group {
            if let course {
                CourseDetailView(course: course)
            } else if failed {
                LoadFailedView { await load() }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            course = try await CourseRepo.course(id: courseID)
            failed = course == nil
        } catch {
            failed = true
        }
    }
}
