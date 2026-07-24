import SwiftUI

/// Distinct from an empty state: shown when a load *failed*, so users with
/// data never see "no data yet" over a network error.
struct LoadFailedView: View {
    var message = "Check your connection and try again."
    let onRetry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await onRetry() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.fairwayGreen)
        }
    }
}

#Preview {
    LoadFailedView {}
}
