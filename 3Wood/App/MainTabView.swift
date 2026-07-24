import SwiftUI

struct MainTabView: View {
    @Environment(AppNavigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        TabView(selection: $nav.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "house") }
                .tag(AppNavigation.Tab.feed)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppNavigation.Tab.search)

            CourseMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppNavigation.Tab.map)

            ListsView()
                .tabItem { Label("Lists", systemImage: "list.number") }
                .tag(AppNavigation.Tab.lists)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppNavigation.Tab.profile)
        }
        .tint(Color.fairwayGreen)
    }
}

#Preview {
    MainTabView()
        .environment(AppNavigation())
}
