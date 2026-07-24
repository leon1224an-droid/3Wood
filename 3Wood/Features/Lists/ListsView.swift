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
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var pendingRemoval: RankedCourse?
    @State private var actionError: String?

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
            .creamScreen()
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
            .confirmationDialog(
                "Remove \(pendingRemoval?.name ?? "this course")?",
                isPresented: .init(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove from Played", role: .destructive) {
                    if let course = pendingRemoval {
                        Task { await remove(course) }
                    }
                }
            } message: {
                Text("This removes it from your ranking and rescores the rest of the bucket.")
            }
            .alert("Something went wrong", isPresented: .init(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    @ViewBuilder
    private var playedList: some View {
        if ranked.isEmpty {
            if loadFailed {
                LoadFailedView { await reload() }
            } else if hasLoaded {
                ContentUnavailableView {
                    Label("No courses yet", systemImage: "figure.golf")
                } description: {
                    Text("Courses you log will appear here, ranked.")
                } actions: {
                    Button("Log your first course") { isLoggingCourse = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
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
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.sand)
                    .swipeActions(edge: .trailing) {
                        Button("Remove") {
                            pendingRemoval = course
                        }
                        .tint(Color.clayRed)
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
            if loadFailed {
                LoadFailedView { await reload() }
            } else {
                ContentUnavailableView(
                    "Nothing saved yet",
                    systemImage: "bookmark",
                    description: Text("Bookmark courses you'd like to play from their detail page.")
                )
            }
        } else {
            List(wantToPlay) { course in
                NavigationLink(value: course) {
                    CourseRow(course: course)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.sand)
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        async let rankedTask = RankingRepo.myRankedCourses()
        async let wantTask = WantToPlayRepo.list()
        do {
            ranked = try await rankedTask
            wantToPlay = try await wantTask
            loadFailed = false
        } catch {
            // Keep whatever was already on screen; only flag when there's
            // nothing to show instead.
            loadFailed = ranked.isEmpty && wantToPlay.isEmpty
        }
        hasLoaded = true
    }

    private func remove(_ course: RankedCourse) async {
        do {
            try await RankingRepo.remove(courseID: course.courseID)
            await reload()
        } catch {
            actionError = "Couldn't remove \(course.name). \(error.localizedDescription)"
        }
    }
}

#Preview {
    ListsView()
}
