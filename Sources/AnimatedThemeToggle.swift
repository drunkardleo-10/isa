import SwiftUI
import AppKit

struct MoonPathShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 25.0
        let sy = rect.height / 25.0
        path.move(to: CGPoint(x: 21.1918 * sx, y: 13.2013 * sy))
        path.addCurve(
            to: CGPoint(x: 19.35 * sx, y: 17.8781 * sy),
            control1: CGPoint(x: 21.0345 * sx, y: 14.9035 * sy),
            control2: CGPoint(x: 20.3957 * sx, y: 16.5257 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 15.2875 * sx, y: 20.8379 * sy),
            control1: CGPoint(x: 18.3044 * sx, y: 19.2305 * sy),
            control2: CGPoint(x: 16.8953 * sx, y: 20.2571 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 10.2713 * sx, y: 21.1574 * sy),
            control1: CGPoint(x: 13.6797 * sx, y: 21.4186 * sy),
            control2: CGPoint(x: 11.9398 * sx, y: 21.5294 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 5.86602 * sx, y: 18.7371 * sy),
            control1: CGPoint(x: 8.60281 * sx, y: 20.7854 * sy),
            control2: CGPoint(x: 7.07479 * sx, y: 19.9459 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 3.4457 * sx, y: 14.3318 * sy),
            control1: CGPoint(x: 4.65725 * sx, y: 17.5283 * sy),
            control2: CGPoint(x: 3.81774 * sx, y: 16.0003 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 3.76526 * sx, y: 9.31561 * sy),
            control1: CGPoint(x: 3.07367 * sx, y: 12.6633 * sy),
            control2: CGPoint(x: 3.18451 * sx, y: 10.9234 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 6.72501 * sx, y: 5.25307 * sy),
            control1: CGPoint(x: 4.346 * sx, y: 7.70783 * sy),
            control2: CGPoint(x: 5.37263 * sx, y: 6.29868 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 11.4018 * sx, y: 3.41132 * sy),
            control1: CGPoint(x: 8.07739 * sx, y: 4.20746 * sy),
            control2: CGPoint(x: 9.69959 * sx, y: 3.56862 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 10.0503 * sx, y: 8.09273 * sy),
            control1: CGPoint(x: 10.4052 * sx, y: 4.75958 * sy),
            control2: CGPoint(x: 9.92564 * sx, y: 6.42077 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 12.0812 * sx, y: 12.5219 * sy),
            control1: CGPoint(x: 10.175 * sx, y: 9.76469 * sy),
            control2: CGPoint(x: 10.8957 * sx, y: 11.3364 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 16.5104 * sx, y: 14.5528 * sy),
            control1: CGPoint(x: 13.2667 * sx, y: 13.7075 * sy),
            control2: CGPoint(x: 14.8384 * sx, y: 14.4281 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 21.1918 * sx, y: 13.2013 * sy),
            control1: CGPoint(x: 18.1823 * sx, y: 14.6775 * sy),
            control2: CGPoint(x: 19.8435 * sx, y: 14.1979 * sy)
        )
        path.closeSubpath()
        return path
    }
}

struct SunRaysShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 25.0
        let sy = rect.height / 25.0

        path.move(to: CGPoint(x: 12.4058 * sx, y: 1.76251 * sy))
        path.addLine(to: CGPoint(x: 12.4058 * sx, y: 3.76251 * sy))

        path.move(to: CGPoint(x: 12.4058 * sx, y: 21.7625 * sy))
        path.addLine(to: CGPoint(x: 12.4058 * sx, y: 23.7625 * sy))

        path.move(to: CGPoint(x: 4.62598 * sx, y: 4.98248 * sy))
        path.addLine(to: CGPoint(x: 6.04598 * sx, y: 6.40248 * sy))

        path.move(to: CGPoint(x: 18.7656 * sx, y: 19.1225 * sy))
        path.addLine(to: CGPoint(x: 20.1856 * sx, y: 20.5425 * sy))

        path.move(to: CGPoint(x: 1.40576 * sx, y: 12.7625 * sy))
        path.addLine(to: CGPoint(x: 3.40576 * sx, y: 12.7625 * sy))

        path.move(to: CGPoint(x: 21.4058 * sx, y: 12.7625 * sy))
        path.addLine(to: CGPoint(x: 23.4058 * sx, y: 12.7625 * sy))

        path.move(to: CGPoint(x: 4.62598 * sx, y: 20.5425 * sy))
        path.addLine(to: CGPoint(x: 6.04598 * sx, y: 19.1225 * sy))

        path.move(to: CGPoint(x: 18.7656 * sx, y: 6.40248 * sy))
        path.addLine(to: CGPoint(x: 20.1856 * sx, y: 4.98248 * sy))

        return path
    }
}

struct SunCenterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 25.0
        let sy = rect.height / 25.0
        let center = CGPoint(x: 12.4058 * sx, y: 12.7625 * sy)
        let radius = 5.0 * min(sx, sy)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}

struct SolarSwitchView: View {
    let isDark: Bool

    var body: some View {
        ZStack {
            ZStack {
                SunCenterShape()
                    .stroke(style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))

                SunRaysShape()
                    .stroke(style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
            }
            .scaleEffect(isDark ? 0.001 : 1.0)
            .opacity(isDark ? 0.0 : 1.0)
            .rotationEffect(.degrees(isDark ? 80 : 0))

            MoonPathShape()
                .stroke(style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                .scaleEffect(isDark ? 1.0 : 0.001)
                .opacity(isDark ? 1.0 : 0.0)
                .rotationEffect(.degrees(isDark ? 0 : -80))
        }
        .frame(width: 12, height: 12)
    }
}

struct AnimatedThemeToggle: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var isHovered: Bool = false

    private var isDark: Bool {
        switch viewModel.theme {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                if isDark {
                    viewModel.theme = .light
                } else {
                    viewModel.theme = .dark
                }
                viewModel.applyAppAppearance()
            }
            PerformanceMonitor.shared.log(event: "Click", details: "Theme toggle button (Current: \(viewModel.theme.rawValue))")
        }) {
            SolarSwitchView(isDark: isDark)
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Appearance: \(viewModel.theme.rawValue.capitalized)")
    }
}
