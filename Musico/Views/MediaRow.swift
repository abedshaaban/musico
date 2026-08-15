import SwiftUI

struct MediaRow: View {
    @EnvironmentObject private var playback: PlaybackController
    let item: LibraryItem
    var trailingText: String?

    private var isCurrent: Bool {
        playback.currentItem?.id == item.id
    }

    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(item: item, size: 48, cornerRadius: 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            isCurrent ? MusicoTheme.magenta.opacity(0.72) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundColor(isCurrent ? .white : .primary)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.subheadline)
                    .foregroundColor(MusicoTheme.secondaryText)
                    .lineLimit(1)
                if let summary = detailSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(MusicoTheme.secondaryText.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(.caption)
                    .foregroundColor(MusicoTheme.secondaryText)
            }
            if isCurrent {
                Image(systemName: playback.isPlaying ? "waveform" : "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(MusicoTheme.magenta)
                    .frame(width: 22)
                    .accessibilityLabel(playback.isPlaying ? "Playing" : "Paused")
            }
        }
        .contentShape(Rectangle())
    }

    private var detailSummary: String? {
        let tags = item.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        return [item.collectionSummary, tags.isEmpty ? nil : tags]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
