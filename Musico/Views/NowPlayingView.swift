import AVKit
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nowPlayingVisualStyle") private var visualStyleRaw = PlayerVisualStyle.vinyl.rawValue
    @State private var isQueuePresented = false
    @State private var isSleepTimerPresented = false

    private var visualStyle: PlayerVisualStyle {
        PlayerVisualStyle(rawValue: visualStyleRaw) ?? .vinyl
    }

    var body: some View {
        NavigationView {
            Group {
                if let item = playback.currentItem {
                    VStack(spacing: 20) {
                        PlayerStylePicker(
                            selection: $visualStyleRaw,
                            styles: PlayerVisualStyle.options(for: item)
                        )
                        .padding(.horizontal, 20)

                        mediaArtwork(for: item)
                            .padding(.horizontal, 20)
                            .id("\(item.id)-\(visualStyleRaw)")

                        VStack(spacing: 5) {
                            Text(item.title)
                                .font(.title2.bold())
                                .lineLimit(2)
                            Text(item.artist)
                                .foregroundColor(.secondary)
                        }

                        if item.kind == .video, visualStyle == .video {
                            Toggle(isOn: $playback.isAudioOnlyMode) {
                                Label("Audio Only", systemImage: "waveform")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 28)
                        }

                        if item.kind == .video && (playback.isAudioOnlyMode || scenePhase != .active) {
                            Label("Audio only — screen off playback enabled", systemImage: "waveform")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        if let sleepLabel = playback.sleepTimerLabel {
                            Label("Sleep in \(sleepLabel)", systemImage: "moon.zzz")
                                .font(.caption)
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
                            Button { isQueuePresented = true } label: {
                                Image(systemName: "list.bullet")
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
                    .padding(.top, 8)
                    .onChange(of: item.id) { _ in
                        normalizeVisualStyle(for: item)
                    }
                    .onAppear {
                        normalizeVisualStyle(for: item)
                    }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if playback.currentItem != nil {
                        Menu {
                            Button { isQueuePresented = true } label: {
                                Label("Up Next", systemImage: "list.bullet")
                            }
                            Button { isSleepTimerPresented = true } label: {
                                Label("Sleep Timer", systemImage: "moon.zzz")
                            }
                            if playback.sleepTimerRemaining != nil {
                                Button("Cancel Sleep Timer", role: .destructive) {
                                    playback.cancelSleepTimer()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $isQueuePresented) {
                QueueView()
            }
            .sheet(isPresented: $isSleepTimerPresented) {
                SleepTimerSheet()
            }
        }
        .musicoStackNavigationStyle()
        .onChange(of: scenePhase) { phase in
            if phase == .background, playback.currentItem?.kind == .video {
                playback.isAudioOnlyMode = true
            }
        }
    }

    @ViewBuilder
    private func mediaArtwork(for item: LibraryItem) -> some View {
        let showVideoPlayer = item.kind == .video
            && visualStyle == .video
            && !playback.isAudioOnlyMode
            && scenePhase == .active

        if showVideoPlayer {
            VideoPlayer(player: playback.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            NowPlayingPlayerVisual(
                item: item,
                style: visualStyle == .video ? .classic : visualStyle,
                isPlaying: playback.isPlaying
            )
        }
    }

    private func normalizeVisualStyle(for item: LibraryItem) {
        let options = PlayerVisualStyle.options(for: item)
        guard !options.contains(visualStyle) else { return }
        visualStyleRaw = options.first?.rawValue ?? PlayerVisualStyle.vinyl.rawValue
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct PlayerStylePicker: View {
    @Binding var selection: String
    let styles: [PlayerVisualStyle]

    private var selectedStyle: PlayerVisualStyle {
        PlayerVisualStyle(rawValue: selection) ?? .vinyl
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(styles) { style in
                    Button {
                        selection = style.rawValue
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: style.systemImage)
                            Text(style.label)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundColor(selectedStyle == style ? .primary : .secondary)
                        .background(
                            Capsule()
                                .fill(
                                    selectedStyle == style
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.secondary.opacity(0.12)
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    selectedStyle == style ? Color.accentColor.opacity(0.35) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
