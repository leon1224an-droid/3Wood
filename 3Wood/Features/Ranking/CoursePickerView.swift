import SwiftUI
import CoreLocation

/// Search-driven course picker. Before the user types it suggests nearby
/// courses — but only when location is already authorized, so the picker never
/// triggers the permission prompt itself (that ask belongs to the map).
///
/// Shared by the ranking flow's "+" entry point and the Want-to-Play sheet, so
/// the copy is caller-supplied.
struct CoursePickerView: View {
    var prompt: String = "Which course did you play?"
    var emptyTitle: String = "Find the course you played"
    var emptyMessage: String = "Search by name or city."
    let onPick: (Course) -> Void

    @State private var viewModel = SearchViewModel()
    @State private var nearby: [Course] = []

    var body: some View {
        List {
            if !viewModel.results.isEmpty {
                ForEach(viewModel.results) { course in
                    pickRow(course)
                }
            } else if viewModel.query.isEmpty, !nearby.isEmpty {
                Section("Near you") {
                    ForEach(nearby) { course in
                        pickRow(course)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.query, prompt: prompt)
        // Same reason as FindFriendsView: a focused search field otherwise
        // takes the whole bar, and the Cancel button that backs out of the
        // flow disappears with it.
        .keepsBackButtonDuringSearch()
        .overlay {
            if viewModel.results.isEmpty, viewModel.query.isEmpty ? nearby.isEmpty : true {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "figure.golf",
                    description: Text(emptyMessage)
                )
            }
        }
        .task {
            guard nearby.isEmpty,
                  let location = await LocationProvider.shared.currentLocationIfAuthorized()
            else { return }
            let lat = location.coordinate.latitude
            let lng = location.coordinate.longitude
            let found = (try? await CourseRepo.inRegion(
                minLat: lat - 0.4, minLng: lng - 0.5, maxLat: lat + 0.4, maxLng: lng + 0.5
            )) ?? []
            nearby = Array(
                found.sorted {
                    location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                        < location.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
                }
                .prefix(15)
            )
        }
    }

    private func pickRow(_ course: Course) -> some View {
        Button {
            onPick(course)
        } label: {
            CourseRow(course: course)
        }
        .foregroundStyle(.primary)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.sand)
    }
}
