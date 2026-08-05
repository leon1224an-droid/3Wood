import SwiftUI

/// Rounds played at this course: when, how many, and a way to add another
/// without re-ranking the course.
struct CourseVisitsSection: View {
    let courseID: Int
    /// Only shown once the course is on the user's Played list — checking in
    /// somewhere you haven't logged would make a round with no ranking.
    let isPlayed: Bool

    @State private var visits: [CourseVisit] = []
    @State private var isLoading = true
    @State private var isCheckingIn = false
    @State private var loadFailed = false
    @State private var showingAll = false
    @State private var pendingDelete: CourseVisit?
    @State private var newDate = Date()
    @State private var actionError: String?

    var body: some View {
        if isPlayed {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(visits.isEmpty ? "Rounds" : "^[\(visits.count) round](inflect: true)")
                        .font(.headline)
                    Spacer()
                    Button {
                        newDate = Date()
                        isCheckingIn = true
                    } label: {
                        Label("Check in again", systemImage: "calendar.badge.plus")
                            .font(.subheadline)
                    }
                    .tint(Color.fairwayGreen)
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if loadFailed, visits.isEmpty {
                    LoadFailedView { await reload() }
                } else if visits.isEmpty {
                    Text("No rounds recorded yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, visit in
                            HStack {
                                Image(systemName: "flag")
                                    .font(.caption)
                                    .foregroundStyle(Color.fairwayGreen)
                                    .accessibilityHidden(true)
                                Text(PlayDate.display(visit.playedOn))
                                    .font(.subheadline)
                                Spacer()
                                if index == 0, shown.count > 1 {
                                    Text("most recent")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Button {
                                    pendingDelete = visit
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundStyle(Color.clayRed)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Remove round on \(PlayDate.display(visit.playedOn))")
                            }
                            if index < shown.count - 1 {
                                Rectangle().fill(Color.sand).frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .card()

                    if visits.count > collapsedLimit {
                        Button(showingAll
                               ? "Show fewer"
                               : "Show all ^[\(visits.count) round](inflect: true)") {
                            withAnimation { showingAll.toggle() }
                        }
                        .font(.subheadline)
                        .tint(Color.fairwayGreen)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .task { await reload() }
            .sheet(isPresented: $isCheckingIn) {
                checkInSheet
            }
            .confirmationDialog(
                "Remove the round on \(PlayDate.display(pendingDelete?.playedOn ?? ""))?",
                isPresented: .init(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove round", role: .destructive) {
                    if let visit = pendingDelete {
                        Task { await remove(visit) }
                    }
                }
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

    /// Defaults to today, but a round is often logged the evening after — or
    /// days later — so the date is editable.
    private var checkInSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Date played", selection: $newDate,
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .creamScreen()
            .navigationTitle("Another round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isCheckingIn = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await checkIn() }
                    }
                }
            }
        }
    }

    /// Long histories collapse: a home course with 30 rounds would otherwise
    /// push photos and reviews off the page.
    private let collapsedLimit = 5

    private var shown: [CourseVisit] {
        showingAll ? visits : Array(visits.prefix(collapsedLimit))
    }

    private func reload() async {
        do {
            visits = try await RankingRepo.visits(courseID: courseID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func checkIn() async {
        isCheckingIn = false
        do {
            try await RankingRepo.logVisit(courseID: courseID, playedOn: newDate)
            await reload()
        } catch {
            actionError = "Couldn't save that round. \(error.localizedDescription)"
        }
    }

    private func remove(_ visit: CourseVisit) async {
        do {
            try await RankingRepo.deleteVisit(id: visit.id)
            await reload()
        } catch {
            actionError = "Couldn't remove that round. \(error.localizedDescription)"
        }
    }
}
