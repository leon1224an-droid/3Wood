import SwiftUI

/// One list's summary row — reused by My Lists, Explore Lists, and a
/// profile's "Their lists" section. Pure display; the caller supplies
/// navigation (matches `CourseRow`'s convention).
struct ListCardRow: View {
    let list: CustomList
    /// Explore/profile contexts show whose list this is; My Lists doesn't.
    var showOwner = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(list.title)
                        .lineLimit(1)
                    Image(systemName: list.visibility == .public ? "globe" : "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(list.visibility == .public ? "Public" : "Private")
                }
                if showOwner, let username = list.ownerUsername {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    metric("flag.checkered", "\(list.courseCount)")
                    metric("bookmark", "\(list.bookmarkCount)")
                    metric("text.bubble", "\(list.commentCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func metric(_ systemImage: String, _ value: String) -> some View {
        Label(value, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }
}
