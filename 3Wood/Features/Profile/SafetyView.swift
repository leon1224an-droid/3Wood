import SwiftUI

/// Guideline 1.2 landing page: states the zero-tolerance policy and points at
/// the report/block mechanisms, in one place that doesn't depend on there
/// being reportable content on screen already.
struct SafetyView: View {
    var body: some View {
        List {
            Section {
                Text("There is zero tolerance for objectionable content or abusive behavior on 3Wood: harassment, hate speech, spam, impersonation, or anything unlawful.")
            }
            .listRowBackground(Color.clear)

            Section("Report") {
                Text("Any review, comment, photo, or user can be reported from its \(Image(systemName: "flag")) or \(Image(systemName: "ellipsis.circle")) menu. Reports are reviewed within 24 hours; violating content and, where warranted, the account that posted it are removed.")
            }
            .listRowBackground(Color.clear)

            Section("Block") {
                Text("Blocking a user hides their content from you everywhere in the app — feed, leaderboard, and course pages — instantly, and also files a report so we can review their account.")
            }
            .listRowBackground(Color.clear)

            Section("Full policy") {
                Link("Terms of service",
                     destination: URL(string: "https://leon1224an-droid.github.io/3Wood/terms.html")!)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Color.sand)
        .creamScreen()
        .navigationTitle("Safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SafetyView() }
}
