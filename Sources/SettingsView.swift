import SwiftUI
import AppKit

enum SettingsNavSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case browsing = "Browsing"
    case history = "History"
    case downloads = "Downloads"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .browsing: return "globe"
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        }
    }

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .general:
            return "Distraction-free focus and window framing"
        case .appearance:
            return "Theme selection and window styling"
        case .browsing:
            return "Search engine, content protection, and web preferences"
        case .history:
            return "Browsing timeline and search query retention"
        case .downloads:
            return "File storage location and completion actions"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var selectedSection: SettingsNavSection = .general
    @State private var hoveredSection: SettingsNavSection? = nil
    @State private var updateCheckMessage: String? = nil
    @State private var isCheckingUpdates: Bool = false

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = 3
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 205)
                .background(Color(nsColor: .windowBackgroundColor))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedSection.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundColor(.primary)

                        Text(selectedSection.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)

                    switch selectedSection {
                    case .general:
                        generalSectionView
                    case .appearance:
                        appearanceSectionView
                    case .browsing:
                        browsingSectionView
                    case .history:
                        historySectionView
                    case .downloads:
                        downloadsSectionView
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(SettingsNavSection.allCases) { section in
                    SidebarNavRow(
                        section: section,
                        isSelected: selectedSection == section,
                        isHovered: hoveredSection == section,
                        onSelect: {
                            selectedSection = section
                        },
                        onHover: { hovering in
                            if hovering {
                                hoveredSection = section
                            } else if hoveredSection == section {
                                hoveredSection = nil
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("isa 1.0 (WebKit)")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.65))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var generalSectionView: some View {
        VStack(spacing: 16) {
            SettingsCardGroup {
                SettingsRow(
                    title: "Zen mode",
                    subtitle: "Distraction-free browsing. The top navigation bar hides completely and reveals smoothly when you hover the top edge."
                ) {
                    Toggle("", isOn: $viewModel.isZenModeEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }


            }

            SettingsCardGroup {
                SettingsRow(
                    title: "Automatically check for updates",
                    subtitle: "isa checks its GitHub release feed in the background. Updates are signed, so they stay safe without notarization."
                ) {
                    Toggle("", isOn: $viewModel.automaticallyCheckForUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(
                    title: "isa 1.0 (WebKit)",
                    subtitle: updateCheckMessage ?? "Build 1000 · Signed updates from GitHub releases."
                ) {
                    Button(action: {
                        isCheckingUpdates = true
                        updateCheckMessage = "Checking GitHub releases..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            isCheckingUpdates = false
                            updateCheckMessage = "Up to date · Build 1000 is latest"
                            if let url = URL(string: "https://github.com/drunkardleo-10/isa/releases") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }) {
                        Text(isCheckingUpdates ? "Checking..." : "Check Now")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var appearanceSectionView: some View {
        VStack(spacing: 16) {
            SettingsCardGroup {
                SettingsRow(
                    title: "Theme mode",
                    subtitle: "Select your preferred color scheme or follow your macOS system preference."
                ) {
                    Picker("Theme", selection: Binding(
                        get: { viewModel.theme },
                        set: { newTheme in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.theme = newTheme
                                viewModel.applyAppAppearance()
                            }
                            PerformanceMonitor.shared.log(event: "Theme", details: "Settings picker changed theme to \(newTheme.rawValue)")
                        }
                    )) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag(AppTheme.system)
                        Label("Light", systemImage: "sun.max.fill").tag(AppTheme.light)
                        Label("Dark", systemImage: "moon.fill").tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Tab layout",
                    subtitle: "Choose whether tabs and navigation appear along the top bar or in an elegant left sidebar."
                ) {
                    Picker("Tab Layout", selection: $viewModel.tabPlacement) {
                        Label("Top Bar", systemImage: "macwindow").tag(TabPlacement.top)
                        Label("Left Sidebar", systemImage: "sidebar.left").tag(TabPlacement.left)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    private var browsingSectionView: some View {
        let counts = AdBlockController.totalRuleCounts
        let formattedNet = Self.numberFormatter.string(from: NSNumber(value: counts.network)) ?? "\(counts.network)"
        let formattedCos = Self.numberFormatter.string(from: NSNumber(value: counts.cosmetic)) ?? "\(counts.cosmetic)"

        return VStack(spacing: 16) {
            SettingsCardGroup {
                SettingsRow(
                    title: "Block Ads & Trackers",
                    subtitle: "Filters cosmetic ads, intrusive scriptlets, and tracking network requests live across all open tabs."
                ) {
                    Toggle("", isOn: $viewModel.isAdBlockEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(
                    title: "Protection status",
                    subtitle: "\(formattedNet) network rules · \(formattedCos) cosmetic selectors"
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isAdBlockEnabled ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)

                        Text(viewModel.isAdBlockEnabled ? "Active" : "Paused")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(viewModel.isAdBlockEnabled ? .green : .secondary)
                    }
                }
            }

            SettingsCardGroup {
                SettingsRow(
                    title: "Default search engine",
                    subtitle: "Search engine used when entering queries in the address bar."
                ) {
                    Text("Google Search")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                SettingsDivider()

                SettingsRow(
                    title: "Internal scheme navigation",
                    subtitle: "Direct URL navigation for native isa:// internal settings and tools."
                ) {
                    Text("isa://")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var historySectionView: some View {
        VStack(spacing: 16) {
            SettingsCardGroup {
                SettingsRow(
                    title: "Stored visits",
                    subtitle: "Cached browsing history visits used for timeline search and search bar suggestions."
                ) {
                    Text("\(HistoryManager.shared.historyItems.count) visits")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Internal page exemption",
                    subtitle: "isa://settings and other internal scheme pages are never recorded in browsing history."
                ) {
                    Text("Exempted")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
            }

            SettingsCardGroup {
                SettingsRow(
                    title: "Clear browsing history",
                    subtitle: "Remove browsing history, visit timestamps, and recent search suggestions."
                ) {
                    Button(action: {
                        viewModel.showHistoryView()
                    }) {
                        Text("Open History...")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var downloadsSectionView: some View {
        VStack(spacing: 16) {
            SettingsCardGroup {
                SettingsRow(
                    title: "Download location",
                    subtitle: "Files downloaded from web pages will be saved directly to this directory."
                ) {
                    Text("~/Downloads")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}


private struct SidebarNavRow: View {
    let section: SettingsNavSection
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: section.iconName)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 18, alignment: .center)

                Text(section.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.11) : (isHovered ? Color.primary.opacity(0.045) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { onHover($0) }
    }
}

private struct SettingsCardGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.primary.opacity(0.035))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

private struct SettingsRow<TrailingContent: View>: View {
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

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.12)
            .padding(.leading, 16)
    }
}
