import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Search coming soon",
                systemImage: "magnifyingglass",
                description: Text("Find any golf course in the US.")
            )
            .navigationTitle("Search")
        }
    }
}

#Preview {
    SearchView()
}
