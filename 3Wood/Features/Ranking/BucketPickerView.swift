import SwiftUI

struct BucketPickerView: View {
    let courseName: String
    let onPick: (Bucket) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("How was \(courseName)?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(Bucket.allCases) { bucket in
                    Button {
                        onPick(bucket)
                    } label: {
                        Label(bucket.label, systemImage: bucket.systemImage)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color(for: bucket))
                }
            }
            Spacer()
        }
        .padding()
    }

    private func color(for bucket: Bucket) -> Color {
        switch bucket {
        case .liked: .fairwayGreen
        case .fine: .orange
        case .disliked: .red
        }
    }
}

#Preview {
    BucketPickerView(courseName: "Pebble Beach Golf Links") { _ in }
}
