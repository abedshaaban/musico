import AVKit
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationView {
            Group {
                if let item = playback.currentItem {
                    VStack(spacing: 24) {
                        mediaArtwork(for: item)
                            .padding(.horizontal, 24)

                        VStack(spacing: 5) {
                            Text(item.title)
                                .font(.title2.bold())
                                .lineLimit(2)
                            Text(item.artist)
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: { min(playback.elapsed, max(playback.duration, 1)) },
                                    set: { playback.seek(to: $0) }
                                ),
                                in: 0...max(playback.duration, 1)
                            )
                            HStack {
                                Text(format(playback.elapsed))
                                Spacer()
                                Text("−\(format(max(playback.duration - playback.elapsed, 0)))")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 28)

                        HStack(spacing: 36) {
                            Button { playback.toggleShuffle() } label: {
                                Image(systemName: "shuffle")
                                    .foregroundColor(playback.isShuffleEnabled ? .accentColor : .secondary)
                            }
                            Button { playback.playPrevious() } label: {
                                Image(systemName: "backward.fill")
                            }
                            Button { playback.togglePlayback() } label: {
                                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 58))
                            }
                            Button { playback.playNext() } label: {
                                Image(systemName: "forward.fill")
                            }
                            Button { playback.seek(to: 0) } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                        .font(.title2)
                        .buttonStyle(.plain)
                        .padding(.horizontal)

                        if let issue = playback.lastPlaybackIssue {
                            Text(issue)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.top)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 52, weight: .light))
                            .foregroundColor(.secondary)
                        Text("Nothing Playing")
                            .font(.title2.bold())
                        Text("Choose an item from Library.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Now Playing")
            .musicoInlineNavigationTitle()
        }
        .musicoStackNavigationStyle()
    }

    @ViewBuilder
    private func mediaArtwork(for item: LibraryItem) -> some View {
        if item.kind == .video {
            VideoPlayer(player: playback.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if library.artworkURL(for: item) != nil {
            LargeMediaArtworkView(item: item)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: "music.note")
                    .font(.system(size: 82, weight: .light))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
