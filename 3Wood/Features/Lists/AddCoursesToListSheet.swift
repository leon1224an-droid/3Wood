import SwiftUI

/// Add or remove courses from a list. Filter by state/type to pre-compile
/// (e.g. "every public course I've ranked in Oregon"), or just scroll and
/// tap. Pre-seeded with the list's current members, so saving diffs the
/// selection into adds and removes in one action — this is the same control
/// for requirement "manually add or remove courses" and "pre-compile with
/// filters," not two separate flows.
struct AddCoursesToListSheet: View {
    let listID: Int
    let currentCourseIDs: Set<Int>
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ranked: [RankedCourse] = []
    @State private var selected: Set<Int>
    @State private var stateFilter: String?
    @State private var typeFilter: CourseTypeFilter = .all
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var errorMessage: String?

    init(listID: Int, currentCourseIDs: Set<Int>, onSaved: @escaping () -> Void) {
        self.listID = listID
        self.currentCourseIDs = currentCourseIDs
        self.onSaved = onSaved
        _selected = State(initialValue: currentCourseIDs)
    }

    /// Only states the caller actually has ranked courses in — no reason to
    /// show all 50 when they've played six.
    private var availableStates: [String] {
        Array(Set(ranked.compactMap(\.state))).sorted()
    }

    private var filtered: [RankedCourse] {
        ranked.filter { course in
            (stateFilter == nil || course.state == stateFilter)
                && typeFilter.matches(course.courseType)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if loadFailed, ranked.isEmpty {
                    LoadFailedView { await load() }
                } else if ranked.isEmpty {
                    ContentUnavailableView(
                        "Nothing ranked yet",
                        systemImage: "flag.checkered",
                        description: Text("Rank a course from Lists → Played before adding it to a list.")
                    )
                } else {
                    VStack(spacing: 0) {
                        filterBar
                        Rectangle().fill(Color.sand).frame(height: 1)
                        if filtered.isEmpty {
                            ContentUnavailableView(
                                "No matches",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try a different state or type.")
                            )
                        } else {
                            List(filtered) { course in
                                CourseToggleRow(
                                    course: course,
                                    isSelected: selected.contains(course.courseID)
                                ) {
                                    if selected.contains(course.courseID) {
                                        selected.remove(course.courseID)
                                    } else {
                                        selected.insert(course.courseID)
                                    }
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .creamScreen()
            .navigationTitle("Add Courses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task { await load() }
            .alert("Couldn't save", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All states") { stateFilter = nil }
                ForEach(availableStates, id: \.self) { state in
                    Button(state) { stateFilter = state }
                }
            } label: {
                Label("State", systemImage: stateFilter == nil
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Filter by state")
            .accessibilityIdentifier("listFilterMenu")

            Menu {
                Picker("Course type", selection: $typeFilter) {
                    ForEach(CourseTypeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Type", systemImage: typeFilter == .all ? "flag" : "flag.fill")
                    .font(.subheadline.weight(.medium))
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Filter by course type")

            if let stateFilter {
                filterChip(stateFilter) { self.stateFilter = nil }
            }
            if typeFilter != .all {
                filterChip(typeFilter.rawValue) { typeFilter = .all }
            }

            Spacer()

            Text("\(selected.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func filterChip(_ label: String, onClear: @escaping () -> Void) -> some View {
        Button(action: onClear) {
            Label(label, systemImage: "xmark.circle.fill")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.fairwayGreen.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.fairwayGreen)
        }
    }

    private func load() async {
        do {
            ranked = try await RankingRepo.myRankedCourses()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let toAdd = selected.subtracting(currentCourseIDs)
        let toRemove = currentCourseIDs.subtracting(selected)
        do {
            if !toAdd.isEmpty {
                _ = try await ListsRepo.addCourses(listID: listID, courseIDs: Array(toAdd))
            }
            for courseID in toRemove {
                try await ListsRepo.removeCourse(listID: listID, courseID: courseID)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CourseToggleRow: View {
    let course: RankedCourse
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).lineLimit(2)
                    Text(course.locationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: course.score, compact: true)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.fairwayGreen : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.sand)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
