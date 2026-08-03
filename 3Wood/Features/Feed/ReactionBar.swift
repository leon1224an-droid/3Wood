import SwiftUI

/// Slack-style reactions: one chip per emoji with its count, yours outlined in
/// green, plus an add button holding the rest of the palette. Tapping a chip
/// toggles only your own presence in it — it doesn't replace a previous choice,
/// because you can hold several at once.
struct ReactionBar: View {
    let reactions: [ReactionSummary]
    /// Compact drops the "add" label to an icon — used in dense feed rows.
    var compact = false
    let onToggle: (String) async -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(reactions) { chip in
                Button {
                    Task { await onToggle(chip.emoji) }
                } label: {
                    HStack(spacing: 4) {
                        Text(chip.emoji)
                            // Matches the add/comment chips beside it; the
                            // inherited .body made emoji chips ~4pt taller.
                            .font(.subheadline)
                        Text("\(chip.count)")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(chip.mine ? Color.fairwayGreen : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(chip.mine
                                       ? Color.fairwayGreen.opacity(0.12)
                                       : Color.clear)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            chip.mine ? Color.fairwayGreen : Color.sand,
                            lineWidth: 1
                        )
                    )
                    // The capsule stays its natural ~32pt so the row doesn't
                    // get heavy; the transparent frame around it brings the
                    // touch area up to the 44pt minimum. Same fix the map pins
                    // needed.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Reaction.label(for: chip.emoji)), \(chip.count)")
                .accessibilityHint(chip.mine ? "Removes your reaction" : "Adds your reaction")
                .accessibilityAddTraits(chip.mine ? [.isButton, .isSelected] : .isButton)
            }

            Menu {
                ForEach(Reaction.all, id: \.self) { emoji in
                    Button {
                        Task { await onToggle(emoji) }
                    } label: {
                        Text("\(emoji)  \(Reaction.label(for: emoji))")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "face.smiling")
                    if !compact {
                        Image(systemName: "plus").font(.caption2)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Color.sand, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Add a reaction")
        }
    }
}
