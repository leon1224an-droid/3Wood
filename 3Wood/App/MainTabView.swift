import SwiftUI

struct MainTabView: View {
    @Environment(AppNavigation.self) private var nav

    /// Re-tapping the active tab pops its stack to the root — the fast way
    /// out of a deep course → profile → course chain.
    private var tabSelection: Binding<AppNavigation.Tab> {
        Binding(
            get: { nav.selectedTab },
            set: { tab in
                if tab == nav.selectedTab {
                    nav.router(for: tab).popToRoot()
                }
                nav.selectedTab = tab
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
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
