import SwiftUI

/// Auth gate: shows the sign-in flow when signed out, the main app when signed in.
/// M1 will introduce SessionStore; until then we go straight to the tabs.
struct RootView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    RootView()
}
