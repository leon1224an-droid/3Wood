import SwiftUI
import MapKit

/// Broad course-type buckets over the messy free-text `course_type` field.
enum CourseTypeFilter: String, CaseIterable, Identifiable {
    case all = "All types"
    case publicCourse = "Public"
    case privateCourse = "Private"
    case semiPrivate = "Semi-private"
    case resort = "Resort"
    case municipal = "Municipal"

    var id: String { rawValue }

    func matches(_ type: String?) -> Bool {
        guard self != .all else { return true }
        let t = (type ?? "").lowercased()
        switch self {
        case .all: return true
        case .publicCourse: return t.contains("public")
        case .privateCourse: return t.contains("private") && !t.contains("semi")
        case .semiPrivate: return t.contains("semi")
        case .resort: return t.contains("resort")
        case .municipal: return t.contains("municipal")
        }
    }
}

private let usStates = [
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI",
    "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN",
    "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
    "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
    "WV", "WI", "WY",
]

struct CourseMapView: View {
    enum ViewMode { case map, list }

    @State private var viewModel = MapViewModel()
    @State private var mode: ViewMode = .map
    @State private var typeFilter: CourseTypeFilter = .all
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8, longitude: -98.6),
            span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
        )
    )

    private var filteredCourses: [Course] {
        viewModel.courses.filter { typeFilter.matches($0.courseType) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .map: mapView
                case .list: listView
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { stateMenu }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) { modeToggle }
            }
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(course: course)
            }
        }
    }

    private var mapView: some View {
        Map(position: $position) {
            ForEach(filteredCourses) { course in
                Annotation(course.name, coordinate: course.coordinate) {
                    NavigationLink(value: course) {
                        ScoreBadge(score: course.avgScore, compact: true)
                    }
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.regionChanged(context.region)
        }
        .overlay(alignment: .top) {
            if viewModel.showZoomHint {
                Text("Zoom in to explore courses")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var listView: some View {
        Group {
            if filteredCourses.isEmpty {
                ContentUnavailableView(
                    "No courses here",
                    systemImage: "mappin.slash",
                    description: Text("Pick a state or move the map, then switch back to the list.")
                )
            } else {
                List(filteredCourses.sorted { ($0.avgScore ?? -1) > ($1.avgScore ?? -1) }) { course in
                    NavigationLink(value: course) {
                        CourseRow(course: course)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var modeToggle: some View {
        Button {
            mode = mode == .map ? .list : .map
        } label: {
            Image(systemName: mode == .map ? "list.bullet" : "map")
        }
        .accessibilityIdentifier("mapModeToggle")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Course type", selection: $typeFilter) {
                ForEach(CourseTypeFilter.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: typeFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("mapFilter")
    }

    private var stateMenu: some View {
        Menu {
            ForEach(usStates, id: \.self) { state in
                Button(state) { Task { await jump(to: state) } }
            }
        } label: {
            Label("State", systemImage: "flag")
        }
    }

    /// Recenter the map and reload courses for the chosen state (works in both
    /// map and list mode).
    private func jump(to state: String) async {
        guard let r = try? await CourseRepo.stateRegion(state),
              let minLat = r.minLat, let minLng = r.minLng,
              let maxLat = r.maxLat, let maxLng = r.maxLng else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(maxLat - minLat, 0.2) * 1.2,
                                   longitudeDelta: max(maxLng - minLng, 0.2) * 1.2)
        )
        position = .region(region)
        viewModel.regionChanged(region)
    }
}

#Preview {
    CourseMapView()
}
