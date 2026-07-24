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
                        Text(bucket.label)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(color(for: bucket),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(bucket == .fine ? Color.inkOnGold : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding()
        .creamScreen()
    }

    // Flat buckets in the same colors as the score badges they produce.
    private func color(for bucket: Bucket) -> Color {
        switch bucket {
        case .liked: .fairwayGreen
        case .fine: .sunriseGold
        case .disliked: .clayRed
        }
    }
}

#Preview {
    BucketPickerView(courseName: "Pebble Beach Golf Links") { _ in }
}
