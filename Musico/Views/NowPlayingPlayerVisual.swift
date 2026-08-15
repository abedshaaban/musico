import SwiftUI
import UIKit

// MARK: - Dispatcher

struct NowPlayingPlayerVisual: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem
    let style: PlayerVisualStyle
    let isPlaying: Bool

    var body: some View {
        Group {
            switch style {
            case .vinyl:
                VinylPlayerVisual(item: item, isPlaying: isPlaying)
            case .compactDisc:
                CompactDiscPlayerVisual(item: item, isPlaying: isPlaying)
            case .cassette:
                CassettePlayerVisual(item: item, isPlaying: isPlaying)
            case .classic, .video:
                ClassicPlayerVisual(item: item)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(style == .cassette ? 1.35 : 1, contentMode: .fit)
    }
}

// MARK: - Shared helpers

private struct TrackArtworkFill: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem

    var body: some View {
        Group {
            if let url = library.artworkURL(for: item),
               let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.18), Color.secondary.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct PlaybackRotation: ViewModifier {
    let isPlaying: Bool
    let duration: Double
    @State private var rotation: Double = 0

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onReceive(timer) { _ in
                guard isPlaying else { return }
                rotation += 360.0 / (duration * 60.0)
                if rotation >= 360 { rotation -= 360 }
            }
    }
}

private extension View {
    func playbackRotation(isPlaying: Bool, duration: Double = 4) -> some View {
        modifier(PlaybackRotation(isPlaying: isPlaying, duration: duration))
    }
}

// MARK: - Vinyl

private struct VinylPlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.10, blue: 0.09),
                            Color(red: 0.05, green: 0.05, blue: 0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

            VStack(spacing: 18) {
                ZStack {
                    tonearm

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(white: 0.14), Color.black],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 140
                                )
                            )
                            .overlay(vinylGrooves)
                            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)

                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .padding(26)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 118, height: 118)
                            .overlay(
                                TrackArtworkFill(item: item)
                                    .clipShape(Circle())
                                    .padding(6)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )

                        Circle()
                            .fill(Color.black)
                            .frame(width: 10, height: 10)
                    }
                    .padding(28)
                    .playbackRotation(isPlaying: isPlaying, duration: 3.6)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                HStack(spacing: 6) {
                    Circle().fill(Color.red.opacity(0.85)).frame(width: 7, height: 7)
                    Text("33⅓ RPM")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.2)
                }
            }
            .padding(20)
        }
    }

    private var vinylGrooves: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.045), lineWidth: 0.8)
                    .padding(CGFloat(18 + index * 7))
            }
        }
    }

    private var tonearm: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5, height: 92)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                )

            Circle()
                .fill(Color(white: 0.82))
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 4, height: 4)
                )
        }
        .rotationEffect(.degrees(isPlaying ? -16 : -28))
        .offset(x: 98, y: -72)
        .animation(.easeInOut(duration: 0.45), value: isPlaying)
    }
}

// MARK: - CD

private struct CompactDiscPlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.13))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)

            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.55),
                                Color.blue.opacity(0.18),
                                Color.purple.opacity(0.22),
                                Color.cyan.opacity(0.18),
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.55)
                            ]),
                            center: .center
                        )
                    )
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.white.opacity(0.18), Color.clear],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 160
                                )
                            )
                    )
                    .overlay(
                        ForEach(0..<24, id: \.self) { index in
                            Circle()
                                .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                                .padding(CGFloat(10 + index * 5))
                        }
                    )

                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 108, height: 108)
                    .overlay(
                        TrackArtworkFill(item: item)
                            .clipShape(Circle())
                            .padding(5)
                    )

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
            .padding(42)
            .playbackRotation(isPlaying: isPlaying, duration: 5)
        }
    }
}

// MARK: - Cassette

private struct CassettePlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.20, blue: 0.22),
                            Color(red: 0.10, green: 0.10, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)

            VStack(spacing: 16) {
                HStack {
                    cassetteWindow
                    Spacer(minLength: 0)
                }

                HStack(spacing: 14) {
                    cassetteReel
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 54)
                            .overlay(
                                TrackArtworkFill(item: item)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(4)
                            )
                        Text("TYPE I")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)

                    cassetteReel
                }
            }
            .padding(22)
        }
    }

    private var cassetteWindow: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.red.opacity(0.8))
                .frame(width: 18, height: 6)
            Text("A")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var cassetteReel: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 58, height: 58)

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .frame(width: 52, height: 52)

            reelSpokes
                .playbackRotation(isPlaying: isPlaying, duration: 2.2)

            Circle()
                .fill(Color(white: 0.18))
                .frame(width: 12, height: 12)
        }
    }

    private var reelSpokes: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 4, height: 22)
                    .offset(y: -11)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
    }
}

// MARK: - Classic

private struct ClassicPlayerVisual: View {
    let item: LibraryItem

    var body: some View {
        LargeMediaArtworkView(item: item)
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}
