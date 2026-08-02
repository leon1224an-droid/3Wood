import SwiftUI

/// Flat editorial tabs: the active tab is underlined in fairway green over a
/// full-width sand hairline. Stands in for the stock segmented control, which
/// reads as system chrome against the cream/paper surfaces.
///
/// Extracted from the Played/Want-to-Play switcher so the leaderboard's
/// week/all-time switcher is the same control rather than a lookalike.
struct SegmentTabs<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = item }
                    } label: {
                        VStack(spacing: 8) {
                            Text(title(item))
                                .font(.subheadline.weight(selection == item ? .semibold : .regular))
                                .foregroundStyle(selection == item ? Color.darkPine : .secondary)
                            Rectangle()
                                .fill(selection == item ? Color.fairwayGreen : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(selection == item ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal)
            Rectangle().fill(Color.sand).frame(height: 1)
        }
    }
}
