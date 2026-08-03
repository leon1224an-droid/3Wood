import SwiftUI

struct ListsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case played = "Played"
        case wantToPlay = "Want to Play"
        var id: String { rawValue }
    }

    enum PlayedSort: String, CaseIterable, Identifiable {
        case myRank = "My ranking"
        case recent = "Recently logged"
        case az = "A to Z"
        var id: String { rawValue }
    }

    @Environment(AppNavigation.self) private var nav
    @State private var segment: Segment = .played
    @State private var playedSort: PlayedSort = .myRank
    @State private var ranked: [RankedCourse] = []
    @State private var wantToPlay: [Course] = []
    @State private var isLoggingCourse = false
    @State private var isAddingWantToPlay = false
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var pendingRemoval: RankedCourse?
    @State private var actionError: String?

    var body: some View {
        @Bindable var router = nav.listsRouter
        NavigationStack(path: $router.path) {
            VStack(spacing: 0) {
                segmentTabs

                switch segment {
                case .played: playedList
                case .wantToPlay: wantToPlayList
                }
            }
            .creamScreen()
            .navigationTitle("My Courses")
            .toolbar {
                if segment == .played, ranked.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Sort", selection: $playedSort) {
                                ForEach(PlayedSort.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Sort courses")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Both lists are added to from here. Logging used to be the
                    // only thing "+" did, which left Want to Play reachable
                    // only from a course's own page.
                    Menu {
                        Button {
                            isLoggingCourse = true
                        } label: {
                            Label("Log a played course", systemImage: "flag.checkered")
                        }
                        Button {
                            isAddingWantToPlay = true
                        } label: {
                            Label("Add to Want to Play", systemImage: "bookmark")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a course")
                    .accessibilityIdentifier("addCourseMenu")
                }
            }
            .appDestinations()
            .fullScreenCover(isPresented: $isLoggingCourse, onDismiss: {
                Task { await reload() }
            }) {
                LogCourseFlow()
            }
            .sheet(isPresented: $isAddingWantToPlay, onDismiss: {
                Task { await reload() }
            }) {
                // Land on the list the course just joined, so the save is visible.
                AddToWantToPlaySheet { segment = .wantToPlay }
            }
            .task { await reload() }
            .onAppear {
                // Adopt cross-tab requests (e.g. Profile's "Want to play" row).
                segment = nav.listsSegment
                Task { await reload() }
            }
            .onChange(of: nav.listsSegment) {
                segment = nav.listsSegment
            }
            .onChange(of: segment) {
                nav.listsSegment = segment
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
        .environment(router)
    }

    private var segmentTabs: some View {
        SegmentTabs(items: Segment.allCases, title: \.rawValue, selection: $segment)
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
                ForEach(Array(sortedRanked.enumerated()), id: \.element.id) { index, course in
                    NavigationLink(value: Destination.courseID(course.courseID)) {
                        HStack(spacing: 12) {
                            // Position numbers only make sense in ranking order.
                            if playedSort == .myRank {
                                Text("\(index + 1)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 28, alignment: .trailing)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).lineLimit(2)
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
                    description: Text("Tap + to save a course you'd like to play, or swipe right on any course in Search.")
                )
            }
        } else {
            List(wantToPlay) { course in
                NavigationLink(value: Destination.course(course)) {
                    CourseRow(course: course)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.sand)
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    private var sortedRanked: [RankedCourse] {
        switch playedSort {
        case .myRank: ranked
        case .recent: ranked.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .az: ranked.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        .environment(AppNavigation())
}
