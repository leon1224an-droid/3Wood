import SwiftUI

struct ListsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case played = "Played"
        case wantToPlay = "Want to Play"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .played
    @State private var ranked: [RankedCourse] = []
    @State private var wantToPlay: [Course] = []
    @State private var isLoggingCourse = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("List", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch segment {
                case .played: playedList
                case .wantToPlay: wantToPlayList
                }
            }
            .navigationTitle("My Courses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isLoggingCourse = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(course: course)
            }
            .navigationDestination(for: RankedCourse.self) { ranked in
                CourseDetailByID(courseID: ranked.courseID)
            }
            .fullScreenCover(isPresented: $isLoggingCourse, onDismiss: {
                Task { await reload() }
            }) {
                LogCourseFlow()
            }
            .task { await reload() }
            .onAppear {
                Task { await reload() }
            }
        }
    }

    @ViewBuilder
    private var playedList: some View {
        if ranked.isEmpty {
            ContentUnavailableView {
                Label("No courses yet", systemImage: "figure.golf")
            } description: {
                Text("Courses you log will appear here, ranked.")
            } actions: {
                Button("Log your first course") { isLoggingCourse = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, course in
                    NavigationLink(value: course) {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).lineLimit(1)
                                Text(course.locationText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ScoreBadge(score: course.score)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    @ViewBuilder
    private var wantToPlayList: some View {
        if wantToPlay.isEmpty {
            ContentUnavailableView(
                "Nothing saved yet",
                systemImage: "bookmark",
                description: Text("Bookmark courses you'd like to play from their detail page.")
            )
        } else {
            List(wantToPlay) { course in
                NavigationLink(value: course) {
                    CourseRow(course: course)
                }
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        async let rankedTask = RankingRepo.myRankedCourses()
        async let wantTask = WantToPlayRepo.list()
        ranked = (try? await rankedTask) ?? ranked
        wantToPlay = (try? await wantTask) ?? wantToPlay
    }
}

#Preview {
    ListsView()
}
