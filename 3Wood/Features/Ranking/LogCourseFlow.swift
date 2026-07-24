import SwiftUI

/// Full-screen modal driving: (optional) course pick → bucket pick →
/// head-to-head comparisons → save → result.
struct LogCourseFlow: View {
    /// Pass a course to skip the picker (e.g. from CourseDetailView).
    var course: Course?
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var model = LogFlowModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .pickCourse:
                    LogCoursePickerView { picked in
                        Task { await model.start(with: picked) }
                    }
                case .loading, .saving:
                    ProgressView()
                case .pickBucket(let course):
                    BucketPickerView(courseName: course.name) { bucket in
                        Task { await model.choose(bucket: bucket) }
                    }
                case .compare(let course, let candidate, let remaining):
                    ComparisonView(
                        newCourseName: course.name,
                        newCourseLocation: course.locationText,
                        candidate: candidate,
                        comparisonsRemaining: remaining
                    ) { answer in
                        Task { await model.answer(answer) }
                    }
                case .done(let course, let score, let position, let bucket):
                    RankResultView(
                        courseName: course.name,
                        score: score,
                        position: position,
                        bucket: bucket
                    ) {
                        onComplete?()
                        dismiss()
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't save", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .creamScreen()
            .navigationTitle(model.step.isDone ? "All set!" : "Log a course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.step.isDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            if let course {
                await model.start(with: course)
            }
        }
    }
}

@Observable
@MainActor
final class LogFlowModel {
    enum Step {
        case pickCourse
        case loading
        case pickBucket(Course)
        case compare(Course, candidate: RankedCourse, remaining: Int)
        case saving
        case done(Course, score: Double, position: Int, bucket: Bucket)
        case failed(String)

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }
    }

    private(set) var step: Step = .pickCourse
    private var course: Course?
    private var bucket: Bucket?
    private var engine: RankingEngine?
    private var ranked: [RankedCourse] = []

    func start(with course: Course) async {
        self.course = course
        step = .loading
        do {
            // Exclude the course itself so re-logging never compares against it.
            ranked = try await RankingRepo.myRankedCourses()
                .filter { $0.courseID != course.id }
            step = .pickBucket(course)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    func choose(bucket: Bucket) async {
        guard let course else { return }
        self.bucket = bucket
        engine = RankingEngine(bucketList: ranked.filter { $0.bucket == bucket })
        await advance(course: course)
    }

    func answer(_ answer: RankingEngine.Answer) async {
        guard let course else { return }
        engine?.answer(answer)
        await advance(course: course)
    }

    private func advance(course: Course) async {
        guard var engine, let bucket else { return }
        if let candidate = engine.candidate {
            step = .compare(course, candidate: candidate, remaining: engine.maxComparisonsRemaining)
        } else {
            step = .saving
            do {
                let position = engine.insertionPosition
                try await RankingRepo.insert(courseID: course.id, bucket: bucket, position: position)
                let score = ScoreMath.score(
                    position: position,
                    bucketCount: engine.bucketList.count + 1,
                    bucket: bucket
                )
                step = .done(course, score: score, position: position, bucket: bucket)
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }
}

/// Search-driven course picker for when the flow starts from the "+" button.
struct LogCoursePickerView: View {
    let onPick: (Course) -> Void
    @State private var viewModel = SearchViewModel()

    var body: some View {
        List(viewModel.results) { course in
            Button {
                onPick(course)
            } label: {
                CourseRow(course: course)
            }
            .foregroundStyle(.primary)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.sand)
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.query, prompt: "Which course did you play?")
        .overlay {
            if viewModel.results.isEmpty {
                ContentUnavailableView(
                    "Find the course you played",
                    systemImage: "figure.golf",
                    description: Text("Search by name or city.")
                )
            }
        }
    }
}
