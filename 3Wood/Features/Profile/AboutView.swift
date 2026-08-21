import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            Section("Course data") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Golf course data © OpenGolfAPI contributors")
                    Text("Licensed under the Open Database License (ODbL) 1.0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Link("OpenGolfAPI", destination: URL(string: "https://opengolfapi.org")!)
                Link("ODbL 1.0 license", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
            }
            .listRowBackground(Color.clear)

            Section("Legal") {
                Link("Privacy policy",
                     destination: URL(string: "https://leon1224an-droid.github.io/3Wood/privacy.html")!)
                Link("Terms of service",
                     destination: URL(string: "https://leon1224an-droid.github.io/3Wood/terms.html")!)
                NavigationLink("Safety") { SafetyView() }
            }
            .listRowBackground(Color.clear)

            Section("Support") {
                Link("Contact support", destination: URL(string: "mailto:3woodapp@gmail.com")!)
            }
            .listRowBackground(Color.clear)

            Section("Open source") {
                Link("supabase-swift", destination: URL(string: "https://github.com/supabase/supabase-swift")!)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Color.sand)
        .creamScreen()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
