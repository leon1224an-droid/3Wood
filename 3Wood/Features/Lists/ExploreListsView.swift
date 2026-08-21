import SwiftUI

/// Public lists from every user (not just people followed) — a discovery
/// feed reachable from the My Lists segment's toolbar.
struct ExploreListsView: View {
    @Environment(Router.self) private var router
    @State private var lists: [CustomList] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if lists.isEmpty {
                if loadFailed {
                    LoadFailedView { await load() }
                } else {
                    ContentUnavailableView(
                        "No public lists yet",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text("Public lists from every golfer on 3Wood will show up here.")
                    )
                }
            } else {
                List(lists) { list in
                    // Button + router.push, not NavigationLink — ListCardRow
                    // already draws its own trailing chevron, so
                    // NavigationLink here would bolt on a second one.
                    Button {
                        router.push(.list(list))
                    } label: {
                        ListCardRow(list: list, showOwner: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.sand)
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .creamScreen()
        .navigationTitle("Explore Lists")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            lists = try await ListsRepo.exploreLists()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
