import AVFoundation
import SwiftUI
import UIKit

struct NowPlayingView: View {
  @EnvironmentObject private var playback: PlaybackController
  @EnvironmentObject private var library: LibraryStore
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("nowPlayingVisualStyle") private var visualStyleRaw = PlayerVisualStyle.vinyl.rawValue
  @State private var isQueuePresented = false
  @State private var isSleepTimerPresented = false
  @State private var isPlaybackSettingsPresented = false

  private var visualStyle: PlayerVisualStyle {
    PlayerVisualStyle(rawValue: visualStyleRaw) ?? .vinyl
  }

  var body: some View {
    NavigationView {
      ZStack {
        MusicoBackground(glowAlignment: .top).ignoresSafeArea()

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
                  .frame(
                    width: shouldShowInlineVideo(for: item)
                      ? layout.videoWidth
                      : layout.artworkWidth
                  )
                  .background(
                    MusicoTheme.magenta.opacity(0.16)
                      .blur(radius: 34)
                      .padding(22)
                  )
                  .shadow(color: MusicoTheme.violet.opacity(0.20), radius: 24, y: 10)
                  .id("\(item.id)-\(visualStyleRaw)")

                VStack(spacing: 5) {
                  Text(item.title)
                    .font(layout.isCompact ? .headline : .title2.bold())
                    .lineLimit(layout.isCompact ? 1 : 2)
                    .minimumScaleFactor(0.82)
                  Text(item.artist)
                    .font(layout.isCompact ? .subheadline : .body)
                    .foregroundColor(MusicoTheme.secondaryText)
                    .lineLimit(1)
                  if let summary = item.collectionSummary {
                    Text(summary)
                      .font(.caption)
                      .foregroundColor(MusicoTheme.secondaryText.opacity(0.84))
                      .lineLimit(1)
                  }
                }
                .padding(.horizontal, layout.horizontalInset)

                if item.kind == .video, visualStyle == .video {
                  Toggle(isOn: $playback.isAudioOnlyMode) {
                    Label("Audio Only", systemImage: "waveform")
                      .font(.subheadline)
                  }
                  .accentColor(MusicoTheme.magenta)
                  .padding(.horizontal, 28)
                }

                if item.kind == .video && (playback.isAudioOnlyMode || scenePhase != .active) {
                  Label("Audio only — screen off playback enabled", systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(MusicoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }

                if let sleepLabel = playback.sleepTimerLabel {
                  Label("Sleep in \(sleepLabel)", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundColor(MusicoTheme.secondaryText)
                }

                if let issue = playback.lastPlaybackIssue {
                  Text(issue)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: layout.controlTopSpacing)

                AudioReactiveWaveform(
                  level: playback.waveformLevel,
                  frequency: playback.waveformFrequency,
                  isPlaying: playback.isPlaying,
                  hasLiveData: playback.hasLiveWaveformData
                )
                .frame(height: layout.waveformHeight)
                .padding(.horizontal, layout.scrubberInset)

                VStack(spacing: layout.scrubberSpacing) {
                  Slider(
                    value: Binding(
                      get: { min(playback.elapsed, max(playback.duration, 1)) },
                      set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 1)
                  )
                  .accentColor(MusicoTheme.magenta)
                  HStack {
                    Text(format(playback.elapsed))
                    Spacer()
                    Text("−\(format(max(playback.duration - playback.elapsed, 0)))")
                  }
                  .font(.caption.monospacedDigit())
                  .foregroundColor(MusicoTheme.secondaryText)
                }
                .padding(.horizontal, layout.scrubberInset)

                HStack(spacing: layout.controlSpacing) {
                  Button {
                    playback.toggleShuffle()
                  } label: {
                    Image(systemName: "shuffle")
                      .foregroundColor(playback.isShuffleEnabled ? MusicoTheme.magenta : MusicoTheme.secondaryText)
                  }
                  Button {
                    playback.playPrevious()
                  } label: {
                    Image(systemName: "backward.fill")
                      .foregroundColor(.white)
                  }
                  Button {
                    playback.togglePlayback()
                  } label: {
                    ZStack {
                      Circle().fill(MusicoTheme.brandGradient)
                      Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: layout.playButtonSize * 0.34, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: playback.isPlaying ? 0 : 1)
                    }
                    .frame(width: layout.playButtonSize, height: layout.playButtonSize)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                    .shadow(color: MusicoTheme.magenta.opacity(0.38), radius: 13, y: 6)
                  }
                  Button {
                    playback.playNext()
                  } label: {
                    Image(systemName: "forward.fill")
                      .foregroundColor(.white)
                  }
                  Button {
                    isQueuePresented = true
                  } label: {
                    Image(systemName: "list.bullet")
                      .foregroundColor(MusicoTheme.secondaryText)
                  }
                }
                .font(layout.isCompact ? .body : .title2)
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .center)

                Color.clear.frame(height: layout.bottomSpacing)
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
              MusicoWaveMark(lineWidth: 10)
                .frame(width: 190, height: 84)
              Text("Nothing Playing")
                .font(.title2.bold())
              Text("Choose an item from Library.")
                .foregroundColor(MusicoTheme.secondaryText)
            }
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
              Button {
                isPlaybackSettingsPresented = true
              } label: {
                Label("Playback Settings", systemImage: "slider.horizontal.3")
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
      .sheet(isPresented: $isPlaybackSettingsPresented) {
        PlaybackSettingsSheet()
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
    if shouldShowInlineVideo(for: item) {
      InlineVideoPlayer(player: playback.player)
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

  private func shouldShowInlineVideo(for item: LibraryItem) -> Bool {
    item.kind == .video
      && visualStyle == .video
      && !playback.isAudioOnlyMode
      && scenePhase == .active
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

/// Displays the player's video without introducing an `AVPlayerViewController`.
/// The controller used by SwiftUI's `VideoPlayer` owns a competing Now Playing
/// session and can disable Musico's manually configured Lock Screen commands when
/// it disappears during a lock/background transition.
private struct InlineVideoPlayer: UIViewRepresentable {
  let player: AVPlayer

  func makeUIView(context: Context) -> PlayerLayerView {
    let view = PlayerLayerView()
    view.player = player
    return view
  }

  func updateUIView(_ view: PlayerLayerView, context: Context) {
    view.player = player
  }

  static func dismantleUIView(_ view: PlayerLayerView, coordinator: Void) {
    view.player = nil
  }
}

private final class PlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  private var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  var player: AVPlayer? {
    get { playerLayer.player }
    set {
      playerLayer.videoGravity = .resizeAspect
      playerLayer.player = newValue
    }
  }
}

struct NowPlayingLayoutMetrics: Equatable {
  let isCompact: Bool
  let artworkWidth: CGFloat
  let videoWidth: CGFloat
  let sectionSpacing: CGFloat
  let horizontalInset: CGFloat
  let scrubberInset: CGFloat
  let controlSpacing: CGFloat
  let playButtonSize: CGFloat
  let scrubberSpacing: CGFloat
  let waveformHeight: CGFloat
  let controlTopSpacing: CGFloat
  let topSpacing: CGFloat
  let bottomSpacing: CGFloat

  init(width: CGFloat, height: CGFloat) {
    isCompact = height < 650
    let availableWidth = max(width - 40, 0)
    // Landscape video is naturally much shorter than square cover art at the
    // same width, so let it use more of the screen while keeping a small inset.
    videoWidth = max(width - (isCompact ? 16 : 24), 0)

    if isCompact {
      artworkWidth = min(availableWidth, max(210, min(250, height * 0.43)))
      sectionSpacing = 10
      horizontalInset = 16
      scrubberInset = 20
      controlSpacing = 27
      playButtonSize = 50
      scrubberSpacing = 3
      waveformHeight = 30
      controlTopSpacing = 4
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
      waveformHeight = 42
      controlTopSpacing = 12
      topSpacing = 8
      bottomSpacing = 12
    }
  }
}

private struct AudioReactiveWaveform: View {
  let level: CGFloat
  let frequency: CGFloat
  let isPlaying: Bool
  let hasLiveData: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
      GeometryReader { geometry in
        let time = timeline.date.timeIntervalSinceReferenceDate
        let displayedLevel = resolvedLevel(at: time)
        let cycles = resolvedCycles

        ZStack {
          ReactiveWaveShape(
            amplitude: displayedLevel,
            cycles: cycles,
            phase: CGFloat(time * 2.4)
          )
          .stroke(
            MusicoTheme.magenta.opacity(0.24),
            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
          )
          .blur(radius: 5)

          ReactiveWaveShape(
            amplitude: displayedLevel,
            cycles: cycles,
            phase: CGFloat(time * 2.4)
          )
          .stroke(
            MusicoTheme.brandGradientHorizontal,
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
          )
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Live audio waveform")
    .accessibilityValue(isPlaying ? "Playing" : "Paused")
  }

  private var resolvedCycles: CGFloat {
    let low: CGFloat = 55
    let high: CGFloat = 4_000
    let clamped = min(max(frequency, low), high)
    let normalized = log2(clamped / low) / log2(high / low)
    return 1.8 + normalized * 5.8
  }

  private func resolvedLevel(at time: TimeInterval) -> CGFloat {
    guard isPlaying else { return 0.04 }
    if hasLiveData {
      return 0.12 + min(max(level, 0), 1) * 0.82
    }
    return 0.22 + CGFloat((sin(time * 2.1) + 1) * 0.06)
  }
}

private struct ReactiveWaveShape: Shape {
  let amplitude: CGFloat
  let cycles: CGFloat
  let phase: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard rect.width > 0, rect.height > 0 else { return path }

    let midY = rect.midY
    let height = max(rect.height * 0.44 * amplitude, 0.8)
    let step = max(rect.width / 100, 1)
    var x: CGFloat = 0

    while x <= rect.width {
      let progress = x / rect.width
      let envelope = 0.58 + 0.42 * sin(.pi * progress)
      let fundamental = sin(progress * cycles * 2 * .pi + phase)
      let harmonic = sin(progress * cycles * 4 * .pi - phase * 0.7) * 0.18
      let point = CGPoint(
        x: x,
        y: midY + (fundamental + harmonic) * height * envelope
      )
      if x == 0 { path.move(to: point) }
      else { path.addLine(to: point) }
      x += step
    }
    return path
  }
}
