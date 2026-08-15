import SwiftUI

enum MusicoTheme {
    static let background = Color(red: 0.015, green: 0.015, blue: 0.095)
    static let backgroundLifted = Color(red: 0.035, green: 0.030, blue: 0.16)
    static let surface = Color(red: 0.065, green: 0.060, blue: 0.18)
    static let elevatedSurface = Color(red: 0.105, green: 0.085, blue: 0.27)
    static let stroke = Color(red: 0.43, green: 0.33, blue: 0.82).opacity(0.32)

    static let yellow = Color(red: 1.00, green: 0.82, blue: 0.27)
    static let coral = Color(red: 1.00, green: 0.31, blue: 0.29)
    static let magenta = Color(red: 0.94, green: 0.12, blue: 0.55)
    static let violet = Color(red: 0.45, green: 0.18, blue: 0.96)
    static let secondaryText = Color(red: 0.68, green: 0.66, blue: 0.78)

    static let brandGradient = LinearGradient(
        colors: [yellow, coral, magenta, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradientHorizontal = LinearGradient(
        colors: [violet, magenta, coral, yellow],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [elevatedSurface, surface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct MusicoBackground: View {
    var glowAlignment: Alignment = .topTrailing

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [MusicoTheme.backgroundLifted, MusicoTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geometry in
                Circle()
                    .fill(MusicoTheme.magenta.opacity(0.16))
                    .frame(width: geometry.size.width * 0.72)
                    .blur(radius: 70)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: glowAlignment
                    )
                    .offset(x: 70, y: -110)

                Circle()
                    .fill(MusicoTheme.violet.opacity(0.12))
                    .frame(width: geometry.size.width * 0.62)
                    .blur(radius: 75)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .offset(x: -80, y: 90)
            }
        }
    }
}

struct MusicoWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width
        let y = rect.height
        var path = Path()

        path.move(to: CGPoint(x: x * 0.02, y: y * 0.58))
        path.addCurve(
            to: CGPoint(x: x * 0.18, y: y * 0.54),
            control1: CGPoint(x: x * 0.08, y: y * 0.82),
            control2: CGPoint(x: x * 0.12, y: y * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: x * 0.34, y: y * 0.57),
            control1: CGPoint(x: x * 0.25, y: y * 0.96),
            control2: CGPoint(x: x * 0.30, y: y * 0.95)
        )
        path.addCurve(
            to: CGPoint(x: x * 0.50, y: y * 0.37),
            control1: CGPoint(x: x * 0.38, y: y * 0.08),
            control2: CGPoint(x: x * 0.42, y: y * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: x * 0.66, y: y * 0.57),
            control1: CGPoint(x: x * 0.58, y: y * 0.08),
            control2: CGPoint(x: x * 0.62, y: y * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: x * 0.82, y: y * 0.54),
            control1: CGPoint(x: x * 0.70, y: y * 0.95),
            control2: CGPoint(x: x * 0.75, y: y * 0.96)
        )
        path.addCurve(
            to: CGPoint(x: x * 0.98, y: y * 0.58),
            control1: CGPoint(x: x * 0.88, y: y * 0.24),
            control2: CGPoint(x: x * 0.92, y: y * 0.82)
        )

        return path
    }
}

struct MusicoWaveMark: View {
    var lineWidth: CGFloat = 13

    var body: some View {
        MusicoWaveShape()
            .stroke(
                MusicoTheme.brandGradientHorizontal,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: MusicoTheme.magenta.opacity(0.52), radius: 12)
            .shadow(color: MusicoTheme.violet.opacity(0.30), radius: 24)
            .accessibilityHidden(true)
    }
}

struct MusicoBrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                MusicoTheme.brandGradient
                    .opacity(isEnabled ? 1 : 0.38)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(
                color: MusicoTheme.magenta.opacity(isEnabled ? 0.26 : 0),
                radius: configuration.isPressed ? 6 : 12,
                y: configuration.isPressed ? 3 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct MusicoCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(MusicoTheme.surfaceGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MusicoTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
    }
}
