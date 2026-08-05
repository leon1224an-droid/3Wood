import SwiftUI
import CoreLocation

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
                    CoursePickerView { picked in
                        Task { await model.start(with: picked) }
                    }
                case .loading, .saving:
                    ProgressView()
                case .pickBucket(let course):
                    BucketPickerView(courseName: course.name) { bucket in
                        model.choose(bucket: bucket)
                    }
                case .pickCompanions(let course):
                    CompanionPickerView(courseName: course.name) { companions in
                        Task { await model.setCompanions(companions) }
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
                case .done(let course, let score, let position, let bucket, let companions):
                    RankResultView(
                        courseID: course.id,
                        courseName: course.name,
                        score: score,
                        position: position,
                        bucket: bucket,
                        companions: companions
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
        case pickCompanions(Course)
        case compare(Course, candidate: RankedCourse, remaining: Int)
        case saving
        case done(Course, score: Double, position: Int, bucket: Bucket, companions: [String])
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
    private var companions: [UUID] = []
    private var companionNames: [String] = []

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

    func choose(bucket: Bucket) {
        guard let course else { return }
        self.bucket = bucket
        step = .pickCompanions(course)
    }

    /// Who you played with, captured before the comparisons so the question is
    /// asked while the round is still the subject. The tags can only be saved
    /// after insert_ranking creates the activity, so they're held until then.
    func setCompanions(_ people: [ProfileSummary]) async {
        guard let course, let bucket else { return }
        self.companions = people.map(\.id)
        self.companionNames = people.map(\.username)
        engine = RankingEngine(bucketList: ranked.filter { $0.bucket == bucket })
        await advance(course: course)
    }

    func answer(_ answer: RankingEngine.Answer) async {
        guard let course else { return }
        engine?.answer(answer)
        await advance(course: course)
    }

    /// insert_ranking creates the activity, so tagging can only happen after
    /// the save. Failing to tag must not fail the round.
    private func attachCompanions(courseID: Int) async {
        guard !companions.isEmpty else { return }
        if let activity = try? await ActivityRepo.myActivity(courseID: courseID) {
            try? await ActivityRepo.setTags(activityID: activity.activityID, userIDs: companions)
        }
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
                await attachCompanions(courseID: course.id)
                step = .done(course, score: score, position: position,
                             bucket: bucket, companions: companionNames)
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }
}
