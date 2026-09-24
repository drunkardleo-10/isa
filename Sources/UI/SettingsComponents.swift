import SwiftUI

struct SettingsPressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct SidebarNavRow: View {
    let section: SettingsNavSection
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: section.iconName)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 18, alignment: .center)
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                Text(section.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary.opacity(0.9) : .secondary))

                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.11))
                            .matchedGeometryEffect(id: "SettingsNavPill", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.045))
                            .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isSelected)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { onHover($0) }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

struct SettingsPillPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let namespace: Namespace.ID
    let pillID: String
    let title: (Option) -> String
    let icon: (Option) -> String

    @State private var hoveredOption: Option? = nil
    @State private var pressedOption: Option? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                let isHovered = hoveredOption == option
                Button(action: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        selection = option
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: icon(option))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)
                        Text(title(option))
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .primary : (isHovered ? .primary.opacity(0.9) : .secondary))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.1), radius: 3, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: pillID, in: namespace)
                            } else if isHovered {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
                    )
                    .scaleEffect(pressedOption == option ? 0.94 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressedOption == option)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredOption = hovering ? option : nil
                    }
                }
                .pressEvents(onPress: { pressedOption = option }, onRelease: { pressedOption = nil })
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool
    var label: String = ""

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                isOn.toggle()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.primary.opacity(isHovered ? 0.18 : 0.13))
                    .frame(width: 36, height: 21)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isOn ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 0.75)
                    )
                    .shadow(color: isOn ? Color.accentColor.opacity(0.3) : Color.clear, radius: isHovered ? 5 : 3, y: 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isOn)
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                    .padding(.horizontal, 3)
                    .scaleEffect(isPressed ? 0.88 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.6), value: isOn)
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressed)
            }
            .frame(width: 36, height: 21)
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.isEmpty ? "Toggle" : label)
        .onHover { isHovered = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .sensoryFeedback(.selection, trigger: isOn)
        .help(label.isEmpty ? "" : label)
    }
}

enum SettingsPillTone {
    case neutral
    case accent
    case destructive

    var foreground: Color {
        switch self {
        case .neutral: return .primary
        case .accent: return .accentColor
        case .destructive: return .red.opacity(0.9)
        }
    }

    var background: Color {
        switch self {
        case .neutral: return Color.primary.opacity(0.08)
        case .accent: return Color.accentColor.opacity(0.12)
        case .destructive: return Color.red.opacity(0.08)
        }
    }

    var border: Color {
        switch self {
        case .neutral: return Color.primary.opacity(0.12)
        case .accent: return Color.accentColor.opacity(0.28)
        case .destructive: return Color.red.opacity(0.2)
        }
    }
}

struct SettingsActionPill: View {
    let title: String
    let systemImage: String?
    var tone: SettingsPillTone = .neutral
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    init(title: String, systemImage: String? = nil, tone: SettingsPillTone = .neutral, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(isEnabled ? tone.foreground : .secondary.opacity(0.45))
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? (isHovered ? tone.background.opacity(1.25) : tone.background) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isEnabled ? (isHovered ? tone.border.opacity(1.4) : tone.border) : Color.primary.opacity(0.06), lineWidth: 0.75)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            )
            .scaleEffect(isPressed && isEnabled ? 0.95 : (isHovered && isEnabled ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressed)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            if isEnabled { isHovered = hovering }
        }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
    }
}

struct PulsingDot: View {
    var color: Color
    var isActive: Bool
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse ? 2.1 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(isActive ? color : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        }
        .frame(width: 14, height: 14)
        .onAppear { pulse = true }
    }
}

struct SettingsCardGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

struct SettingsRow<TrailingContent: View>: View {
    let title: String
    let subtitle: String
    let trailing: TrailingContent

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> TrailingContent) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.12)
            .padding(.leading, 16)
    }
}

struct PressEventModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventModifier(onPress: onPress, onRelease: onRelease))
    }
}
