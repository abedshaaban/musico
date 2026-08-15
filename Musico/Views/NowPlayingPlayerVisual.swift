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
                ClassicPlayerVisual(item: item, isPlaying: isPlaying)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(style == .cassette ? 1.4 : 1, contentMode: .fit)
    }
}

// MARK: - Shared helpers

private struct TrackArtworkFill: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem

    var body: some View {
        Group {
            if let uiImage = library.artworkImage(for: item, targetSize: 360) {
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
    @Environment(\.scenePhase) private var scenePhase
    let isPlaying: Bool
    let duration: Double

    func body(content: Content) -> some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isPlaying || scenePhase != .active
            )
        ) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration)
            content.rotationEffect(.degrees((cycle / duration) * 360))
        }
    }
}

private extension View {
    func playbackRotation(isPlaying: Bool, duration: Double = 4) -> some View {
        modifier(PlaybackRotation(isPlaying: isPlaying, duration: duration))
    }
}

private struct DeckChassis: View {
    var cornerRadius: CGFloat = 24
    var top: Color
    var bottom: Color

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [top, bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.30), radius: 20, y: 12)
    }
}

// MARK: - Vinyl

private struct VinylPlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            DeckChassis(
                cornerRadius: 28,
                top: Color(red: 0.13, green: 0.11, blue: 0.10),
                bottom: Color(red: 0.05, green: 0.05, blue: 0.05)
            )

            VStack(spacing: 16) {
                ZStack {
                    platter

                    record
                        .padding(30)
                        .playbackRotation(isPlaying: isPlaying, duration: 3.6)

                    discSheen
                        .padding(30)
                        .allowsHitTesting(false)

                    tonearm
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

                statusRow
            }
            .padding(20)
        }
    }

    private var platter: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.30), Color(white: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(16)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.10), Color(white: 0.05)],
                        center: .center,
                        startRadius: 40,
                        endRadius: 160
                    )
                )
                .padding(20)

            strobeDots
                .playbackRotation(isPlaying: isPlaying, duration: 3.6)
        }
    }

    private var strobeDots: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2 - 22
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                ForEach(0..<36, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 2.5, height: 2.5)
                        .position(
                            x: center.x + radius * cos(CGFloat(index) * .pi / 18),
                            y: center.y + radius * sin(CGFloat(index) * .pi / 18)
                        )
                }
            }
        }
    }

    private var record: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.16), Color(white: 0.03)],
                        center: .center,
                        startRadius: 30,
                        endRadius: 150
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

            grooveBands

            Circle()
                .fill(Color(white: 0.05))
                .padding(94)

            Circle()
                .fill(Color.white)
                .frame(width: 112, height: 112)
                .overlay(
                    TrackArtworkFill(item: item)
                        .clipShape(Circle())
                        .padding(4)
                )
                .overlay(
                    Circle().stroke(Color.black.opacity(0.10), lineWidth: 1)
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.85), Color(white: 0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 11, height: 11)
                .overlay(Circle().fill(Color.black.opacity(0.7)).frame(width: 4, height: 4))
        }
    }

    private var grooveBands: some View {
        ZStack {
            ForEach(0..<22, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(index % 5 == 0 ? 0.09 : 0.035), lineWidth: 0.7)
                    .padding(CGFloat(10 + index * 4))
            }
        }
    }

    private var discSheen: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .white.opacity(0.10), location: 0.08),
                        .init(color: .clear, location: 0.18),
                        .init(color: .clear, location: 0.50),
                        .init(color: .white.opacity(0.07), location: 0.58),
                        .init(color: .clear, location: 0.68),
                        .init(color: .clear, location: 1.00)
                    ]),
                    center: .center,
                    angle: .degrees(-45)
                )
            )
            .blendMode(.plusLighter)
    }

    private var tonearm: some View {
        GeometryReader { geometry in
            let pivot = CGPoint(x: geometry.size.width - 34, y: 30)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.55), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .position(pivot)

                armAssembly
                    .position(x: pivot.x, y: pivot.y)
            }
        }
    }

    private var armAssembly: some View {
        VStack(spacing: 0) {
            // Counterweight above pivot
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.35), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 16, height: 20)

            // Pivot bearing
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 18, height: 18)

            // Arm tube
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.95), Color(white: 0.62)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 4.5, height: 108)

            // Headshell + stylus
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.30), Color(white: 0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 12, height: 22)
                Triangle()
                    .fill(Color(white: 0.75))
                    .frame(width: 5, height: 5)
            }
        }
        .offset(y: 62)
        .rotationEffect(.degrees(isPlaying ? 22 : 8), anchor: .center)
        .animation(.spring(response: 0.8, dampingFraction: 0.75), value: isPlaying)
        .shadow(color: .black.opacity(0.35), radius: 3, x: -2, y: 3)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isPlaying ? Color.green : Color.red.opacity(0.5))
                .frame(width: 6, height: 6)
                .shadow(color: isPlaying ? .green.opacity(0.7) : .clear, radius: 4)
                .animation(.easeInOut(duration: 0.3), value: isPlaying)

            Text("33⅓")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(isPlaying ? 0.75 : 0.35))

            Text("45")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.22))

            Spacer(minLength: 0)

            Text("DIRECT DRIVE · STEREO")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.28))
                .tracking(1.2)
        }
        .padding(.horizontal, 6)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - CD

private struct CompactDiscPlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            DeckChassis(
                cornerRadius: 24,
                top: Color(red: 0.17, green: 0.18, blue: 0.20),
                bottom: Color(red: 0.07, green: 0.08, blue: 0.10)
            )

            VStack(spacing: 14) {
                displayBar

                discTray

                transportRow
            }
            .padding(18)
        }
    }

    private var displayBar: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.75))
            .frame(height: 30)
            .overlay(
                HStack(spacing: 8) {
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan.opacity(isPlaying ? 0.9 : 0.4))
                        .playbackRotation(isPlaying: isPlaying, duration: 2.5)

                    Text(isPlaying ? "PLAY" : "PAUSE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(isPlaying ? 0.95 : 0.45))
                        .tracking(1.5)

                    if isPlaying {
                        levelMeter
                    }

                    Spacer(minLength: 0)

                    Text("DIGITAL AUDIO")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                        .tracking(1.2)
                }
                .padding(.horizontal, 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )

    }

    private var levelMeter: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan.opacity(0.8 - Double(index) * 0.13))
                    .frame(width: 2.5, height: CGFloat(4 + index * 2))
            }
        }
    }

    private var discTray: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.55), Color.black.opacity(0.30)],
                        center: .center,
                        startRadius: 30,
                        endRadius: 200
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.02), Color.white.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )

            disc
                .padding(20)
                .playbackRotation(isPlaying: isPlaying, duration: 2.8)

            discSheen
                .padding(20)
                .allowsHitTesting(false)

            hub
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.1, contentMode: .fit)
    }

    private var disc: some View {
        ZStack {
            // Silver base
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.86), Color(white: 0.62)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)

            // Iridescent data band
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hue: 0.55, saturation: 0.55, brightness: 0.95).opacity(0.45),
                            Color(hue: 0.72, saturation: 0.45, brightness: 0.90).opacity(0.35),
                            Color(hue: 0.90, saturation: 0.35, brightness: 0.95).opacity(0.30),
                            Color(hue: 0.12, saturation: 0.40, brightness: 0.98).opacity(0.35),
                            Color(hue: 0.38, saturation: 0.45, brightness: 0.92).opacity(0.35),
                            Color(hue: 0.55, saturation: 0.55, brightness: 0.95).opacity(0.45)
                        ]),
                        center: .center
                    )
                )
                .blendMode(.overlay)

            // Fine data tracks
            ForEach(0..<26, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    .padding(CGFloat(6 + index * 4))
            }

            // Printed label (artwork) center portion
            Circle()
                .fill(Color.white)
                .frame(width: 118, height: 118)
                .overlay(
                    TrackArtworkFill(item: item)
                        .clipShape(Circle())
                )
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))

            // Clear hub ring
            Circle()
                .fill(Color.black.opacity(0.30))
                .frame(width: 44, height: 44)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                )

            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 18, height: 18)
        }
    }

    private var discSheen: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .white.opacity(0.35), location: 0.06),
                        .init(color: .clear, location: 0.14),
                        .init(color: .clear, location: 0.48),
                        .init(color: .white.opacity(0.22), location: 0.56),
                        .init(color: .clear, location: 0.64),
                        .init(color: .clear, location: 1.00)
                    ]),
                    center: .center,
                    angle: .degrees(-60)
                )
            )
            .blendMode(.plusLighter)
            .mask(
                Circle().strokeBorder(Color.white, lineWidth: 70).padding(4)
            )
    }

    private var hub: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.75), Color(white: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
    }

    private var transportRow: some View {
        HStack(spacing: 16) {
            transportButton(icon: "backward.fill", prominent: false)
            transportButton(icon: isPlaying ? "pause.fill" : "play.fill", prominent: true)
            transportButton(icon: "forward.fill", prominent: false)
        }
    }

    private func transportButton(icon: String, prominent: Bool) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: prominent
                        ? [Color.white.opacity(0.20), Color.white.opacity(0.08)]
                        : [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: prominent ? 40 : 34, height: prominent ? 40 : 34)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: prominent ? 13 : 10, weight: .semibold))
                    .foregroundColor(.white.opacity(prominent ? 0.95 : 0.5))
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(prominent ? 0.22 : 0.10), lineWidth: 1)
            )
    }
}

// MARK: - Cassette

private struct CassettePlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            shell

            VStack(spacing: 10) {
                screwRow(topEdge: true)

                labelCard

                screwRow(topEdge: false)
            }
            .padding(14)
        }
    }

    private var shell: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.16, blue: 0.17),
                        Color(red: 0.09, green: 0.09, blue: 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
    }

    private func screwRow(topEdge: Bool) -> some View {
        HStack {
            screw
            Spacer(minLength: 0)
            if topEdge {
                Text("STEREO · TYPE I · 90 MIN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
                    .tracking(1.2)
            } else {
                bottomHoles
            }
            Spacer(minLength: 0)
            screw
        }
        .padding(.horizontal, 4)
    }

    private var screw: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(white: 0.45), Color(white: 0.15)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 8
                )
            )
            .frame(width: 9, height: 9)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 5, weight: .heavy))
                    .foregroundColor(.black.opacity(0.6))
            )
    }

    private var bottomHoles: some View {
        HStack(spacing: 26) {
            capstanHole
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.6))
                .frame(width: 26, height: 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            capstanHole
        }
    }

    private var capstanHole: some View {
        Circle()
            .fill(Color.black.opacity(0.7))
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var labelCard: some View {
        VStack(spacing: 0) {
            labelHeader

            reelWindow
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.92, blue: 0.86),
                            Color(red: 0.88, green: 0.85, blue: 0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
        )
        .frame(maxHeight: .infinity)
    }

    private var labelHeader: some View {
        HStack(spacing: 8) {
            Text("A")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 0.82, green: 0.26, blue: 0.22))
                )

            Text(item.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .italic()
                .foregroundColor(.black.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 26, height: 26)
                .overlay(
                    TrackArtworkFill(item: item)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.82, green: 0.26, blue: 0.22).opacity(0.85))
                .frame(height: 2)
                .padding(.horizontal, 12)
        }
    }

    private var reelWindow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.06), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.35), lineWidth: 2)
                )

            HStack {
                reel(tapeAmount: 0.55)
                Spacer(minLength: 0)
                tapeBridge
                Spacer(minLength: 0)
                reel(tapeAmount: 0.95)
            }
            .padding(.horizontal, 12)

            // Window glass reflection
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.10), location: 0),
                            .init(color: .clear, location: 0.35)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
        .frame(maxHeight: .infinity)
    }

    private var tapeBridge: some View {
        VStack(spacing: 3) {
            Rectangle()
                .fill(Color(red: 0.42, green: 0.28, blue: 0.15))
                .frame(height: 3)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(isPlaying ? 0.18 : 0.06))
                        .frame(height: 1)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    private func reel(tapeAmount: CGFloat) -> some View {
        ZStack {
            // Tape pack
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.30, green: 0.20, blue: 0.11),
                            Color(red: 0.45, green: 0.30, blue: 0.16)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 34
                    )
                )
                .frame(width: 24 + 38 * tapeAmount, height: 24 + 38 * tapeAmount)
                .animation(.easeInOut(duration: 0.4), value: tapeAmount)

            // Hub
            Circle()
                .fill(Color(white: 0.92))
                .frame(width: 26, height: 26)

            reelTeeth
                .playbackRotation(isPlaying: isPlaying, duration: 1.8)

            Circle()
                .stroke(Color(white: 0.55), lineWidth: 1.5)
                .frame(width: 26, height: 26)
        }
        .frame(width: 64, height: 64)
    }

    private var reelTeeth: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.25))
                    .frame(width: 3.5, height: 9)
                    .offset(y: -9)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
    }
}

// MARK: - Classic

private struct ClassicPlayerVisual: View {
    let item: LibraryItem
    let isPlaying: Bool

    var body: some View {
        ZStack {
            // Ambient glow from artwork
            LargeMediaArtworkView(item: item)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(26)
                .blur(radius: 40)
                .opacity(isPlaying ? 0.55 : 0.30)
                .animation(.easeInOut(duration: 0.8), value: isPlaying)
                .allowsHitTesting(false)

            // Artwork card
            LargeMediaArtworkView(item: item)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(26)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .padding(26)
                )
                .overlay(
                    // Glass highlight
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0),
                            .init(color: .clear, location: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(26)
                    .allowsHitTesting(false)
                )
                .scaleEffect(isPlaying ? 1.0 : 0.94)
                .shadow(color: .black.opacity(isPlaying ? 0.30 : 0.18), radius: isPlaying ? 24 : 14, y: isPlaying ? 14 : 8)
                .animation(.spring(response: 0.55, dampingFraction: 0.8), value: isPlaying)
        }
    }
}
