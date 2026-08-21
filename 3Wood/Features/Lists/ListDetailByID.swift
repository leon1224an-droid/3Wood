import SwiftUI

/// Loads a list the caller only has an id for — the alert feed pushes this,
/// since a notification carries no CustomList row with it.
struct ListDetailByID: View {
    let listID: Int

    @State private var list: CustomList?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let list {
                ListDetailView(list: list)
            } else if isLoading {
                ProgressView()
            } else if loadFailed {
                LoadFailedView { await load() }
            } else {
                ContentUnavailableView(
                    "This list is gone",
                    systemImage: "questionmark.circle",
                    description: Text("It may have been removed or made private.")
                )
                .creamScreen()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            list = try await ListsRepo.detail(listID: listID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
