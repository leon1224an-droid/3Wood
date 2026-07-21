import SwiftUI

struct ListsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No courses yet",
                systemImage: "figure.golf",
                description: Text("Courses you log will appear here, ranked.")
            )
            .navigationTitle("My Courses")
        }
    }
}

#Preview {
    ListsView()
}
