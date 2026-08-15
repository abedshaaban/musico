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
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

            VStack(spacing: 18) {
                ZStack {
                    platterMat

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
                            .overlay(strobeDots)
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

                HStack(spacing: 10) {
                    Circle()
                        .fill(isPlaying ? Color.green.opacity(0.9) : Color.red.opacity(0.55))
                        .frame(width: 7, height: 7)
                        .shadow(color: isPlaying ? .green.opacity(0.6) : .clear, radius: 4)
                        .animation(.easeInOut(duration: 0.3), value: isPlaying)

                    Text("33⅓ RPM")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(1.2)

                    Spacer(minLength: 0)

                    Text("STEREO")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                        .tracking(1.4)
                }
                .padding(.horizontal, 4)
            }
            .padding(20)
        }
    }

    private var platterMat: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(white: 0.08), Color(white: 0.04)],
                    center: .center,
                    startRadius: 40,
                    endRadius: 150
                )
            )
            .padding(18)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    .padding(18)
            )
    }

    private var strobeDots: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 4, height: 4)
                    .offset(y: -52)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.19, blue: 0.21),
                            Color(red: 0.08, green: 0.09, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isPlaying ? Color.green.opacity(0.95) : Color.orange.opacity(0.7))
                        .frame(width: 7, height: 7)
                        .shadow(color: isPlaying ? .green.opacity(0.55) : .clear, radius: 5)
                        .animation(.easeInOut(duration: 0.3), value: isPlaying)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .frame(height: 22)
                        .overlay(
                            HStack(spacing: 6) {
                                Image(systemName: "opticaldisc")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.cyan.opacity(0.75))
                                Text(isPlaying ? "READING" : "STANDBY")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green.opacity(isPlaying ? 0.85 : 0.45))
                                    .tracking(0.8)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                        )

                    Spacer(minLength: 0)

                    cdAntennaHub
                        .scaleEffect(0.55)
                        .opacity(0.85)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .padding(8)
                        )

                    spinningDisc
                        .padding(22)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1.05, contentMode: .fit)

                HStack(spacing: 18) {
                    cdControlButton(icon: "backward.fill", isActive: false)
                    cdControlButton(icon: isPlaying ? "pause.fill" : "play.fill", isActive: true)
                    cdControlButton(icon: "forward.fill", isActive: false)
                }
                .padding(.top, 2)
            }
            .padding(18)
        }
    }

    private var spinningDisc: some View {
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
                                colors: [Color.white.opacity(0.22), Color.clear],
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

            cdAntennaHub
        }
        .playbackRotation(isPlaying: isPlaying, duration: 5)
    }

    private var cdAntennaHub: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.68)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )

            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(6, 14 - CGFloat(index) * 2.2), height: 2.5)
                    .offset(y: -6 - CGFloat(index) * 3.2)
            }

            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 5, height: 5)
                .offset(y: -22)
        }
    }

    private func cdControlButton(icon: String, isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
            .frame(width: 34, height: 34)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? .white.opacity(0.9) : .white.opacity(0.45))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.18 : 0.08), lineWidth: 1)
            )
    }
}

// MARK: - Cassette

private struct CassettePlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool
    @State private var ribbonPhase: CGFloat = 0

    private let ribbonTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

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
                    Text("90")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }

                ZStack {
                    tapeRibbon

                    HStack(spacing: 14) {
                        cassetteReel(isLeft: true)
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .frame(height: 54)
                                .overlay(
                                    TrackArtworkFill(item: item)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .padding(4)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                )
                            Text("TYPE I")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)

                        cassetteReel(isLeft: false)
                    }
                }
            }
            .padding(22)
        }
        .onReceive(ribbonTimer) { _ in
            guard isPlaying else { return }
            ribbonPhase += 0.035
            if ribbonPhase > 1 { ribbonPhase -= 1 }
        }
        .onChange(of: isPlaying) { playing in
            if !playing { ribbonPhase = 0 }
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

    private var tapeRibbon: some View {
        GeometryReader { geometry in
            let reelRadius: CGFloat = 29
            let centerY = geometry.size.height * 0.5
            let leftCenter = CGPoint(x: reelRadius + 2, y: centerY)
            let rightCenter = CGPoint(x: geometry.size.width - reelRadius - 2, y: centerY)
            let labelTop = centerY - 27
            let labelBottom = centerY + 27

            ZStack {
                tapeSegment(
                    from: CGPoint(x: leftCenter.x + reelRadius * 0.55, y: leftCenter.y - 4),
                    to: CGPoint(x: geometry.size.width * 0.5 - 8, y: labelTop + 6),
                    shimmerOffset: ribbonPhase
                )
                tapeSegment(
                    from: CGPoint(x: leftCenter.x + reelRadius * 0.55, y: leftCenter.y + 4),
                    to: CGPoint(x: geometry.size.width * 0.5 - 8, y: labelBottom - 6),
                    shimmerOffset: ribbonPhase + 0.5
                )
                tapeSegment(
                    from: CGPoint(x: geometry.size.width * 0.5 + 8, y: labelTop + 6),
                    to: CGPoint(x: rightCenter.x - reelRadius * 0.55, y: rightCenter.y - 4),
                    shimmerOffset: ribbonPhase + 0.25
                )
                tapeSegment(
                    from: CGPoint(x: geometry.size.width * 0.5 + 8, y: labelBottom - 6),
                    to: CGPoint(x: rightCenter.x - reelRadius * 0.55, y: rightCenter.y + 4),
                    shimmerOffset: ribbonPhase + 0.75
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func tapeSegment(from start: CGPoint, to end: CGPoint, shimmerOffset: CGFloat) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.22, blue: 0.12).opacity(0.35),
                    Color(red: 0.52, green: 0.36, blue: 0.20).opacity(isPlaying ? 0.95 : 0.65),
                    Color(red: 0.38, green: 0.25, blue: 0.14).opacity(0.35)
                ],
                startPoint: UnitPoint(x: shimmerOffset, y: 0.5),
                endPoint: UnitPoint(x: shimmerOffset + 0.45, y: 0.5)
            ),
            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
    }

    private func cassetteReel(isLeft: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 58, height: 58)

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .frame(width: 52, height: 52)

            Circle()
                .stroke(
                    Color(red: 0.48, green: 0.32, blue: 0.18).opacity(isPlaying ? 0.55 : 0.35),
                    lineWidth: isLeft ? 7 : 11
                )
                .frame(width: isLeft ? 36 : 44, height: isLeft ? 36 : 44)
                .animation(.easeInOut(duration: 0.35), value: isPlaying)

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
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.97, green: 0.96, blue: 0.94),
                                    Color(red: 0.90, green: 0.88, blue: 0.84)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

            LargeMediaArtworkView(item: item)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        .padding(18)
                )
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.08)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(18)
                    .allowsHitTesting(false)
                )
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }
}
