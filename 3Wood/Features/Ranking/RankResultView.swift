import SwiftUI

struct RankResultView: View {
    let courseID: Int
    let courseName: String
    let score: Double
    let position: Int
    let bucket: Bucket
    /// Already tagged during the flow — the screen shows them rather than
    /// asking the same question a second time.
    var companions: [String] = []
    let onDone: () -> Void

    @State private var isWritingReview = false
    @State private var isAddingPhotos = false
    @State private var hasReviewed = false
    @State private var isTagging = false
    @State private var activityID: Int?
    @State private var tagged: [String] = []

    var body: some View {
        ScrollView {
          VStack(spacing: 24) {
            Spacer(minLength: 24)
            Text(courseName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            // Vintage scorecard flourish: the score set huge in the brand
            // face between hairline rules.
            VStack(spacing: 12) {
                rule
                Text(String(format: "%.1f", score))
                    .font(.custom("Righteous-Regular", fixedSize: 88))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                    .accessibilityLabel(String(format: "Score %.1f", score))
                rule
            }

            Text("#\(position) of your \"\(bucket.label)\" courses")
                .font(.subheadline.smallCaps())
                .foregroundStyle(Color.darkPine)

            // Who you played with, while the round is still fresh in mind.
            if tagged.isEmpty {
                Button("Add playing partners") { isTagging = true }
                    .font(.subheadline.weight(.medium))
                    .tint(Color.fairwayGreen)
                    .disabled(activityID == nil)
            } else {
                Button {
                    isTagging = true
                } label: {
                    Text("with \(tagged.map { "@\($0)" }.formatted(.list(type: .and)))")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .tint(Color.fairwayGreen)
            }

            Spacer()

            // Strike while the round is fresh — reviews and photos mostly
            // happen here, not on a later visit to the course page.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { reviewButton; photosButton }
                VStack(spacing: 4) { reviewButton; photosButton }
            }
            .font(.subheadline.weight(.medium))
            .tint(Color.fairwayGreen)
            .padding(.bottom, 8)

            Button {
                onDone()
            } label: {
                Text("Done")
            }
            .buttonStyle(.primary)
          }
          .padding()
          .frame(maxWidth: .infinity)
        }
        .creamScreen()
        .sheet(isPresented: $isWritingReview) {
            WriteReviewSheet(courseID: courseID, existing: nil) {
                hasReviewed = true
            }
        }
        .sheet(isPresented: $isAddingPhotos) {
            NavigationStack {
                ScrollView {
                    CoursePhotosSection(courseID: courseID)
                        .padding()
                }
                .creamScreen()
                .navigationTitle("Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isAddingPhotos = false }
                    }
                }
            }
        }
        .sheet(isPresented: $isTagging) {
            if let activityID {
                TagFriendsSheet(activityID: activityID, alreadyTagged: tagged) { tagged = $0 }
            }
        }
        // insert_ranking creates the activity; look it up so tagging has
        // something to attach to.
        .task {
            tagged = companions
            activityID = (try? await ActivityRepo.myActivity(courseID: courseID))?.activityID
        }
    }

    private var reviewButton: some View {
        Button(hasReviewed ? "Review saved ✓" : "Write a review") {
            isWritingReview = true
        }
        .disabled(hasReviewed)
        .frame(minHeight: 44)
    }

    private var photosButton: some View {
        Button("Add photos") { isAddingPhotos = true }
            .frame(minHeight: 44)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.sand)
            .frame(height: 1)
            .padding(.horizontal, 48)
    }

    /// Same banding as ScoreBadge; the gold band uses brass so the huge
    /// numeral stays readable on cream.
    private var scoreColor: Color {
        switch score {
        case 6.7...: .fairwayGreen
        case 3.4..<6.7: .medalGold
        default: .clayRed
        }
    }
}

#Preview {
    RankResultView(courseID: 1, courseName: "Pebble Beach Golf Links", score: 8.4, position: 1, bucket: .liked) {}
}
