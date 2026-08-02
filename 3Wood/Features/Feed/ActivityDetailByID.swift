import SwiftUI

/// Loads an activity the caller only has an id for — the alert feed pushes
/// this, since a notification carries no feed row with it.
struct ActivityDetailByID: View {
    let activityID: Int

    @State private var item: FeedItem?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let item {
                ActivityDetailView(item: item)
            } else if isLoading {
                ProgressView()
            } else if loadFailed {
                LoadFailedView { await load() }
            } else {
                ContentUnavailableView(
                    "This activity is gone",
                    systemImage: "questionmark.circle",
                    description: Text("It may have been removed.")
                )
                .creamScreen()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            item = try await ActivityRepo.activity(id: activityID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
