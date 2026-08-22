import SwiftUI

struct ListsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case played = "Played"
        case wantToPlay = "Want to Play"
        case myLists = "My Lists"
        case saved = "Saved"
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
    @State private var myLists: [CustomList] = []
    @State private var savedLists: [CustomList] = []
    @State private var isLoggingCourse = false
    @State private var isAddingWantToPlay = false
    @State private var isCreatingList = false
    @State private var pendingListDeletion: CustomList?
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
                case .myLists: myListsSection
                case .saved: savedListsSection
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
                if segment == .myLists || segment == .saved {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            router.push(.exploreLists)
                        } label: {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        .accessibilityLabel("Explore lists")
                        .accessibilityIdentifier("exploreListsButton")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    switch segment {
                    case .myLists:
                        Button {
                            isCreatingList = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New list")
                        .accessibilityIdentifier("newListButton")
                    case .saved:
                        EmptyView()
                    case .played, .wantToPlay:
                        // Both lists are added to from here. Logging used to be
                        // the only thing "+" did, which left Want to Play
                        // reachable only from a course's own page.
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
            .sheet(isPresented: $isCreatingList) {
                ListEditorSheet(editing: nil) { created in
                    myLists.insert(created, at: 0)
                }
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
            .confirmationDialog(
                "Delete \"\(pendingListDeletion?.title ?? "this list")\"?",
                isPresented: .init(
                    get: { pendingListDeletion != nil },
                    set: { if !$0 { pendingListDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete list", role: .destructive) {
                    if let list = pendingListDeletion {
                        Task { await deleteList(list) }
                    }
                }
            } message: {
                Text("This can't be undone. Courses stay in your ranking — only the list goes away.")
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
                                if let played = course.lastPlayedOn {
                                    Text(playedLine(for: course, on: played))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
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

    @ViewBuilder
    private var myListsSection: some View {
        if myLists.isEmpty {
            if loadFailed {
                LoadFailedView { await reload() }
            } else if hasLoaded {
                ContentUnavailableView {
                    Label("No lists yet", systemImage: "list.star")
                } description: {
                    Text("Build a ranked list from courses you've already played — a state trip, a favorites round-up, whatever you want to name it.")
                } actions: {
                    Button("Create your first list") { isCreatingList = true }
                        .buttonStyle(.borderedProminent)
                    Button("Explore public lists") { nav.listsRouter.push(.exploreLists) }
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        } else {
            List {
                Section {
                    Button {
                        nav.listsRouter.push(.exploreLists)
                    } label: {
                        Label("Explore public lists", systemImage: "sparkle.magnifyingglass")
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(myLists) { list in
                    // Button + router.push, not NavigationLink — ListCardRow
                    // already draws its own trailing chevron (matching
                    // OtherProfileView's "Their courses" rows), so
                    // NavigationLink here would bolt on a second one.
                    // my_lists() doesn't return owner_id/is_mine (every row is
                    // already the caller's own) — set it here so the detail
                    // screen's manage menu doesn't flash "Report" before its
                    // own reload() corrects it.
                    Button {
                        nav.listsRouter.push(.list(asMine(list)))
                    } label: {
                        ListCardRow(list: list)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.sand)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            pendingListDeletion = list
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
    private var savedListsSection: some View {
        if savedLists.isEmpty {
            if loadFailed {
                LoadFailedView { await reload() }
            } else if hasLoaded {
                ContentUnavailableView {
                    Label("Nothing saved yet", systemImage: "bookmark")
                } description: {
                    Text("Bookmark a public list to find it again here.")
                } actions: {
                    Button("Explore public lists") { nav.listsRouter.push(.exploreLists) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        } else {
            List {
                ForEach(savedLists) { list in
                    // Button + router.push, not NavigationLink — same
                    // double-chevron reasoning as myListsSection above.
                    Button {
                        nav.listsRouter.push(.list(list))
                    } label: {
                        ListCardRow(list: list, showOwner: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.sand)
                    .swipeActions(edge: .trailing) {
                        Button("Remove") {
                            Task { await unbookmark(list) }
                        }
                        .tint(Color.clayRed)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    /// "Played 12 Mar 2026" — with a round count once there's more than one.
    private func playedLine(for course: RankedCourse, on played: String) -> String {
        let date = PlayDate.display(played)
        guard let count = course.visitCount, count > 1 else { return "Played \(date)" }
        return "Played \(date) · \(count) rounds"
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
        async let listsTask = ListsRepo.myLists()
        async let savedTask = ListsRepo.myBookmarkedLists()
        // Independent try?s, not one do/catch — a failure on any one segment
        // (e.g. My Lists) must not abort the others before they're assigned.
        // A shared `do` here previously meant a Played-tab failure could
        // silently leave My Lists empty with no error shown.
        let newRanked = try? await rankedTask
        let newWantToPlay = try? await wantTask
        let newMyLists = try? await listsTask
        let newSaved = try? await savedTask
        if let newRanked { ranked = newRanked }
        if let newWantToPlay { wantToPlay = newWantToPlay }
        if let newMyLists { myLists = newMyLists }
        if let newSaved { savedLists = newSaved }
        // Keep whatever was already on screen; only flag when there's
        // nothing to show instead.
        loadFailed = ranked.isEmpty && wantToPlay.isEmpty && myLists.isEmpty && savedLists.isEmpty
        hasLoaded = true
    }

    private func asMine(_ list: CustomList) -> CustomList {
        var copy = list
        copy.isMine = true
        return copy
    }

    private func deleteList(_ list: CustomList) async {
        do {
            try await ListsRepo.delete(listID: list.id)
            myLists.removeAll { $0.id == list.id }
        } catch {
            actionError = "Couldn't delete \"\(list.title)\". \(error.localizedDescription)"
        }
    }

    private func unbookmark(_ list: CustomList) async {
        savedLists.removeAll { $0.id == list.id }
        do {
            try await ListsRepo.toggleBookmark(listID: list.id)
        } catch {
            actionError = "Couldn't remove \"\(list.title)\" from Saved. \(error.localizedDescription)"
            await reload()
        }
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
