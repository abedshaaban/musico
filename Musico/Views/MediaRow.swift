import SwiftUI

struct MediaRow: View {
    let item: LibraryItem
    var trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

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
