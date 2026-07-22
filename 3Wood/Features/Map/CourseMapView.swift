import SwiftUI
import MapKit

struct CourseMapView: View {
    @State private var viewModel = MapViewModel()
    /// Continental US on first launch.
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8, longitude: -98.6),
            span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
        )
    )

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(viewModel.courses) { course in
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
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(course: course)
            }
        }
    }
}

#Preview {
    CourseMapView()
}
