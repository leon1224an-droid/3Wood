import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ListsView()
                .tabItem { Label("Lists", systemImage: "list.number") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            CourseMapView()
                .tabItem { Label("Map", systemImage: "map") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Color.fairwayGreen)
    }
}

#Preview {
    MainTabView()
}
