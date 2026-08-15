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
          GeometryReader { geometry in
            let layout = NowPlayingLayoutMetrics(
              width: geometry.size.width,
              height: geometry.size.height
            )

            ScrollView(.vertical, showsIndicators: layout.isCompact) {
              VStack(spacing: layout.sectionSpacing) {
                mediaArtwork(for: item)
                  .frame(width: layout.artworkWidth)
                  .id("\(item.id)-\(visualStyleRaw)")

                VStack(spacing: 5) {
                  Text(item.title)
                    .font(layout.isCompact ? .headline : .title2.bold())
                    .lineLimit(layout.isCompact ? 1 : 2)
                    .minimumScaleFactor(0.82)
                  Text(item.artist)
                    .font(layout.isCompact ? .subheadline : .body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                .padding(.horizontal, layout.horizontalInset)

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

                VStack(spacing: layout.scrubberSpacing) {
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
                .padding(.horizontal, layout.scrubberInset)

                HStack(spacing: layout.controlSpacing) {
                  Button {
                    playback.toggleShuffle()
                  } label: {
                    Image(systemName: "shuffle")
                      .foregroundColor(playback.isShuffleEnabled ? .accentColor : .secondary)
                  }
                  Button {
                    playback.playPrevious()
                  } label: {
                    Image(systemName: "backward.fill")
                  }
                  Button {
                    playback.togglePlayback()
                  } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                      .font(.system(size: layout.playButtonSize))
                  }
                  Button {
                    playback.playNext()
                  } label: {
                    Image(systemName: "forward.fill")
                  }
                  Button {
                    isQueuePresented = true
                  } label: {
                    Image(systemName: "list.bullet")
                  }
                }
                .font(layout.isCompact ? .body : .title2)
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                if let issue = playback.lastPlaybackIssue {
                  Text(issue)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: layout.bottomSpacing)
              }
              .frame(
                maxWidth: .infinity,
                minHeight: geometry.size.height,
                alignment: .top
              )
              .padding(.top, layout.topSpacing)
            }
          }
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
          if let item = playback.currentItem {
            Menu {
              Menu {
                ForEach(PlayerVisualStyle.options(for: item)) { style in
                  Button {
                    visualStyleRaw = style.rawValue
                  } label: {
                    Label(
                      style.label,
                      systemImage: visualStyle == style
                        ? "checkmark.circle.fill"
                        : style.systemImage
                    )
                  }
                }
              } label: {
                Label("Player Appearance", systemImage: "rectangle.stack")
              }

              Divider()

              Button {
                isQueuePresented = true
              } label: {
                Label("Up Next", systemImage: "list.bullet")
              }
              Button {
                isSleepTimerPresented = true
              } label: {
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
    let showVideoPlayer =
      item.kind == .video
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

struct NowPlayingLayoutMetrics: Equatable {
  let isCompact: Bool
  let artworkWidth: CGFloat
  let sectionSpacing: CGFloat
  let horizontalInset: CGFloat
  let scrubberInset: CGFloat
  let controlSpacing: CGFloat
  let playButtonSize: CGFloat
  let scrubberSpacing: CGFloat
  let topSpacing: CGFloat
  let bottomSpacing: CGFloat

  init(width: CGFloat, height: CGFloat) {
    isCompact = height < 650
    let availableWidth = max(width - 40, 0)

    if isCompact {
      artworkWidth = min(availableWidth, max(210, min(250, height * 0.43)))
      sectionSpacing = 10
      horizontalInset = 16
      scrubberInset = 20
      controlSpacing = 27
      playButtonSize = 50
      scrubberSpacing = 3
      topSpacing = 4
      bottomSpacing = 8
    } else {
      artworkWidth = min(availableWidth, height * 0.50)
      sectionSpacing = 20
      horizontalInset = 20
      scrubberInset = 28
      controlSpacing = 36
      playButtonSize = 58
      scrubberSpacing = 6
      topSpacing = 8
      bottomSpacing = 12
    }
  }
}
