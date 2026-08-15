import SwiftUI

struct MediaRow: View {
    let item: LibraryItem
    var trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(item: item, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
