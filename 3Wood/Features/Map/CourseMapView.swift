import SwiftUI
import MapKit

struct CourseMapView: View {
    /// Continental US at launch until course pins arrive in M2.
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8, longitude: -98.6),
            span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
        )
    )

    var body: some View {
        NavigationStack {
            Map(position: $position)
                .navigationTitle("Map")
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    CourseMapView()
}
