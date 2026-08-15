import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var library: LibraryStore
    let onOpenNowPlaying: () -> Void

    var body: some View {
        if let item = playback.currentItem {
            HStack(spacing: 12) {
                Button(action: onOpenNowPlaying) {
                    HStack(spacing: 12) {
                        MediaArtworkView(item: item, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(item.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { playback.togglePlayback() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }
}
