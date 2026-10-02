import SwiftUI
import AppKit

enum DeleteButtonStatus: Equatable {
    case idle
    case deleted
    case kept
}

struct BinBodyShape: Shape {
    var top: CGFloat

    var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        let clampedTop = max(1.0, min(19.0, top))
        let wall = max(1.0, 20.0 - clampedTop)

        path.move(to: CGPoint(x: 19 * sx, y: clampedTop * sy))
        path.addLine(to: CGPoint(x: 19 * sx, y: (clampedTop + wall) * sy))
        path.addArc(
            center: CGPoint(x: 17 * sx, y: 20 * sy),
            radius: 2 * sx,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 7 * sx, y: 22 * sy))
        path.addArc(
            center: CGPoint(x: 7 * sx, y: 20 * sy),
            radius: 2 * sx,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 5 * sx, y: clampedTop * sy))
        return path
    }
}

struct BinLidShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0

        path.move(to: CGPoint(x: 3 * sx, y: 6 * sy))
        path.addLine(to: CGPoint(x: 21 * sx, y: 6 * sy))

        path.move(to: CGPoint(x: 8 * sx, y: 6 * sy))
        path.addLine(to: CGPoint(x: 8 * sx, y: 4 * sy))
        path.addArc(
            center: CGPoint(x: 10 * sx, y: 4 * sy),
            radius: 2 * sx,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 14 * sx, y: 2 * sy))
        path.addArc(
            center: CGPoint(x: 14 * sx, y: 4 * sy),
            radius: 2 * sx,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 16 * sx, y: 6 * sy))
        return path
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        path.move(to: CGPoint(x: 4 * sx, y: 12.5 * sy))
        path.addLine(to: CGPoint(x: 9.5 * sx, y: 18 * sy))
        path.addLine(to: CGPoint(x: 20 * sx, y: 7 * sy))
        return path
    }
}

struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        path.move(to: CGPoint(x: 6 * sx, y: 6 * sy))
        path.addLine(to: CGPoint(x: 18 * sx, y: 18 * sy))
        path.move(to: CGPoint(x: 18 * sx, y: 6 * sy))
        path.addLine(to: CGPoint(x: 6 * sx, y: 18 * sy))
        return path
    }
}

struct NotchTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct AnimatedDeleteButton: View {
    var size: CGFloat = 26
    var onConfirm: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isOpen: Bool = false
    @State private var status: DeleteButtonStatus = .idle
    @State private var settleScale: CGFloat = 1.0
    @State private var checkmarkProgress: CGFloat = 1.0
    @State private var isConfirmHovered: Bool = false
    @State private var isCancelHovered: Bool = false
    @State private var isMainHovered: Bool = false
    @State private var resetTask: DispatchWorkItem? = nil

    private var tileWidth: CGFloat { size }
    private var panelWidth: CGFloat { size * (84.0 / 48.0) }
    private var totalWidth: CGFloat { isOpen ? (tileWidth + panelWidth) : tileWidth }
    private var cornerRadius: CGFloat { size * (12.0 / 48.0) }
    private var circleSize: CGFloat { size * (28.0 / 48.0) }
    private var iconSize: CGFloat { size * (24.0 / 48.0) }
    private var circleIconSize: CGFloat { size * (14.0 / 48.0) }

    private var surfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 38/255, green: 38/255, blue: 38/255)
            : Color(red: 244/255, green: 244/255, blue: 249/255)
    }

    private var recessColor: Color {
        colorScheme == .dark
            ? Color(red: 27/255, green: 27/255, blue: 27/255)
            : Color(red: 231/255, green: 231/255, blue: 239/255)
    }

    private var glyphColor: Color {
        colorScheme == .dark
            ? Color(red: 155/255, green: 154/255, blue: 167/255)
            : Color(red: 134/255, green: 133/255, blue: 147/255)
    }

    private var circleHoverColor: Color {
        colorScheme == .dark
            ? Color(red: 44/255, green: 44/255, blue: 44/255)
            : Color(red: 250/255, green: 250/255, blue: 253/255)
    }

    private let accentColor = Color(red: 255/255, green: 95/255, blue: 46/255)

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(surfaceColor)
                .frame(width: totalWidth, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), lineWidth: 0.5)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.05),
                    radius: max(1, size * 0.05),
                    x: 0,
                    y: 1
                )

            if isOpen {
                HStack(spacing: 0) {
                    Spacer(minLength: tileWidth)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(recessColor)
                            .frame(width: panelWidth, height: size)

                        NotchTriangleShape()
                            .fill(recessColor)
                            .frame(width: max(2, size * 0.09), height: max(4, size * 0.22))
                            .offset(x: -max(2, size * 0.08))

                        HStack(spacing: max(3, size * 0.1)) {
                            Button(action: {
                                resolve(next: .deleted)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(isConfirmHovered ? circleHoverColor : surfaceColor)
                                        .frame(width: circleSize, height: circleSize)
                                        .shadow(
                                            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                                            radius: 1,
                                            x: 0,
                                            y: 0.5
                                        )

                                    CheckmarkShape()
                                        .stroke(
                                            accentColor,
                                            style: StrokeStyle(
                                                lineWidth: max(1.5, size * (3.5 / 48.0)),
                                                lineCap: .round,
                                                lineJoin: .round
                                            )
                                        )
                                        .frame(width: circleIconSize, height: circleIconSize)
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isConfirmHovered = $0 }
                            .scaleEffect(isConfirmHovered ? 1.05 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isConfirmHovered)
                            .help("Confirm delete")

                            Button(action: {
                                resolve(next: .kept)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(isCancelHovered ? circleHoverColor : surfaceColor)
                                        .frame(width: circleSize, height: circleSize)
                                        .shadow(
                                            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                                            radius: 1,
                                            x: 0,
                                            y: 0.5
                                        )

                                    CrossShape()
                                        .stroke(
                                            glyphColor,
                                            style: StrokeStyle(
                                                lineWidth: max(1.5, size * (3.5 / 48.0)),
                                                lineCap: .round,
                                                lineJoin: .round
                                            )
                                        )
                                        .frame(width: circleIconSize, height: circleIconSize)
                                }
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isCancelHovered = $0 }
                            .scaleEffect(isCancelHovered ? 1.05 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isCancelHovered)
                            .help("Cancel")
                        }
                        .frame(width: panelWidth, height: size)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity
                ))
            }

            Button(action: {
                if isOpen {
                    resolve(next: .kept)
                } else {
                    status = .idle
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                        isOpen = true
                    }
                }
            }) {
                ZStack {
                    if status == .deleted {
                        CheckmarkShape()
                            .trim(from: 0, to: checkmarkProgress)
                            .stroke(
                                accentColor,
                                style: StrokeStyle(
                                    lineWidth: max(1.5, size * (2.5 / 48.0)),
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: iconSize, height: iconSize)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        ZStack {
                            BinBodyShape(top: isOpen ? 13.5 : 6.0)
                                .stroke(
                                    isMainHovered ? (colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.75)) : glyphColor,
                                    style: StrokeStyle(
                                        lineWidth: max(1.6, size * (2.4 / 48.0)),
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )

                            BinLidShape()
                                .stroke(
                                    isMainHovered ? (colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.75)) : glyphColor,
                                    style: StrokeStyle(
                                        lineWidth: max(1.6, size * (2.4 / 48.0)),
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                                .rotationEffect(
                                    .degrees(isOpen ? -35 : 0),
                                    anchor: UnitPoint(x: 3.0 / 24.0, y: 6.0 / 24.0)
                                )
                        }
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(settleScale)
                        .transition(.opacity)
                    }
                }
                .frame(width: tileWidth, height: size)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isMainHovered = $0 }
            .help(isOpen ? "Cancel" : "Delete")
        }
        .frame(width: totalWidth, height: size, alignment: .leading)
        .animation(.spring(response: 0.44, dampingFraction: 0.74), value: isOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)
        .onExitCommand {
            if isOpen {
                resolve(next: .kept)
            }
        }
    }

    private func resolve(next: DeleteButtonStatus) {
        resetTask?.cancel()
        resetTask = nil

        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
            isOpen = false
            status = next
        }

        if next == .deleted {
            checkmarkProgress = 0.0
            withAnimation(.easeOut(duration: 0.35)) {
                checkmarkProgress = 1.0
            }
            onConfirm?()

            let work = DispatchWorkItem {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    self.status = .idle
                }
            }
            resetTask = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
        } else if next == .kept {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                settleScale = 0.86
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    self.settleScale = 1.0
                }
            }
            onCancel?()

            let work = DispatchWorkItem {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    self.status = .idle
                }
            }
            resetTask = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
}
