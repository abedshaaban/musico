import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var library: LibraryStore
    let onOpenNowPlaying: () -> Void

    var body: some View {
        if let item = playback.currentItem {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.white.opacity(0.06)
                        MusicoTheme.brandGradientHorizontal
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 3)

                HStack(spacing: 12) {
                    Button(action: onOpenNowPlaying) {
                        HStack(spacing: 12) {
                            MediaArtworkView(item: item, size: 44, cornerRadius: 11)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(item.artist)
                                    .font(.caption)
                                    .foregroundColor(MusicoTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { playback.togglePlayback() } label: {
                        ZStack {
                            Circle().fill(MusicoTheme.brandGradient)
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 38, height: 38)
                        .shadow(color: MusicoTheme.magenta.opacity(0.34), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(MusicoTheme.surfaceGradient)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(MusicoTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.38), radius: 16, y: 8)
        } else {
            EmptyView()
        }
    }

    private var progress: CGFloat {
        guard playback.duration > 0 else { return 0 }
        return CGFloat(min(max(playback.elapsed / playback.duration, 0), 1))
    }
}
