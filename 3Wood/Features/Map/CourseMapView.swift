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
    @State private var citySearch = ""
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
            .searchable(text: $citySearch, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Jump to a city")
            .onSubmit(of: .search) { Task { await jumpToPlace(citySearch) } }
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
            UserAnnotation()
            // Only draw pins once zoomed in enough — at continental zoom the
            // hundreds of overlapping badges read as dark blobs.
            if !viewModel.showZoomHint {
                ForEach(filteredCourses) { course in
                    Annotation(course.name, coordinate: course.coordinate) {
                        NavigationLink(value: course) {
                            // Score capsules only for rated courses; unrated
                            // ones get a quiet dot so dense metros stay legible
                            // and the rated badges pop.
                            if course.avgScore != nil {
                                ScoreBadge(score: course.avgScore, compact: true)
                            } else {
                                Circle()
                                    .fill(Color.darkPine)
                                    .overlay(Circle().strokeBorder(Color.cream, lineWidth: 1.5))
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .accessibilityLabel(course.name)
                    }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.regionChanged(context.region)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if viewModel.showZoomHint {
                    Text("Zoom in to explore courses")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
                activeFilterChip
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var activeFilterChip: some View {
        if typeFilter != .all {
            Button {
                typeFilter = .all
            } label: {
                Label(typeFilter.rawValue, systemImage: "xmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.fairwayGreen.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.fairwayGreen)
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
                List {
                    if typeFilter != .all {
                        activeFilterChip
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredCourses.sorted { ($0.avgScore ?? -1) > ($1.avgScore ?? -1) }) { course in
                        NavigationLink(value: course) {
                            CourseRow(course: course)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.sand)
                    }
                }
                .listStyle(.plain)
                .creamScreen()
            }
        }
    }

    private var modeToggle: some View {
        Button {
            mode = mode == .map ? .list : .map
        } label: {
            Image(systemName: mode == .map ? "list.bullet" : "map")
        }
        .accessibilityLabel(mode == .map ? "Show as list" : "Show as map")
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
        .accessibilityLabel("Filter by course type")
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
        .accessibilityLabel("Jump to a state")
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

    /// Geocode a typed city/place and recenter the map there.
    private func jumpToPlace(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return }
        let region = MKCoordinateRegion(
            center: item.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
        mode = .map
        position = .region(region)
        viewModel.regionChanged(region)
    }
}

#Preview {
    CourseMapView()
}
