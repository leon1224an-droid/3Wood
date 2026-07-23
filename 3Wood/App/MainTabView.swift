import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "house") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            CourseMapView()
                .tabItem { Label("Map", systemImage: "map") }

            ListsView()
                .tabItem { Label("Lists", systemImage: "list.number") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Color.fairwayGreen)
    }
}

#Preview {
    MainTabView()
}
