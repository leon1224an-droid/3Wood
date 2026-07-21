import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Profile",
                systemImage: "person.crop.circle",
                description: Text("Sign-in and profiles arrive in the next milestone.")
            )
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
