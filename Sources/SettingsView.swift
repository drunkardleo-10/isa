import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
            return "Browsing timeline and recently visited websites"
        case .downloads:
            return "Downloaded files and storage location"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject private var historyManager: HistoryManager = HistoryManager.shared
    @ObservedObject private var downloadManager: DownloadManager = DownloadManager.shared
    @State private var selectedSection: SettingsNavSection = .general
    @State private var hoveredSection: SettingsNavSection? = nil
    @State private var updateCheckMessage: String? = nil
    @State private var isCheckingUpdates: Bool = false
    @State private var historySearchText: String = ""
    @State private var showClearBrowsingDataSheet: Bool = false

    private var filteredHistoryItems: [HistoryItem] {
        historyManager.search(query: historySearchText)
    }

    private var groupedHistoryItems: [(String, [HistoryItem])] {
        historyManager.groupedHistory(for: filteredHistoryItems)
    }

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
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showClearBrowsingDataSheet) {
            ClearBrowsingDataSheet(historyManager: historyManager, isPresented: $showClearBrowsingDataSheet)
        }
        .onAppear {
            syncSectionWithURL()
        }
        .onChange(of: viewModel.activeTab.currentURL) { _ in
            syncSectionWithURL()
        }
    }

    private func syncSectionWithURL() {
        guard let url = viewModel.activeTab.currentURL, url.scheme?.lowercased() == "isa" else { return }
        let host = url.host?.lowercased() ?? ""
        if host == "history" {
            selectedSection = .history
        } else if host == "downloads" {
            selectedSection = .downloads
        } else if host == "appearance" {
            selectedSection = .appearance
        } else if host == "browsing" {
            selectedSection = .browsing
        } else if host == "general" || host == "settings" {
            selectedSection = .general
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("Search history…", text: $historySearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !historySearchText.isEmpty {
                        Button(action: { historySearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.045))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
                )

                Spacer()

                Text("\(filteredHistoryItems.count) visits")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())

                Button(action: {
                    showClearBrowsingDataSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clear Data...")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(historyManager.historyItems.isEmpty ? .secondary.opacity(0.4) : .red.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(historyManager.historyItems.isEmpty ? 0.03 : 0.08))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.red.opacity(historyManager.historyItems.isEmpty ? 0.05 : 0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(historyManager.historyItems.isEmpty)
            }
            .padding(.bottom, 4)

            if historyManager.historyItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("No Browsing History")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Websites you visit will appear here.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            } else if filteredHistoryItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("No Results Found")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("No history matching \"\(historySearchText)\"")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedHistoryItems, id: \.0) { groupName, items in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(groupName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(items.count)")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                            }
                            .padding(.horizontal, 4)

                            SettingsCardGroup {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    SettingsHistoryRowView(
                                        item: item,
                                        onSelect: { inNewTab in
                                            if let url = URL(string: item.url) {
                                                viewModel.openHistoryURL(url, inNewTab: inNewTab)
                                            }
                                        },
                                        onDelete: {
                                            historyManager.deleteItem(id: item.id)
                                        }
                                    )

                                    if index < items.count - 1 {
                                        SettingsDivider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var downloadsSectionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCardGroup {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text("Download folder")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.primary)

                        Text("~/Downloads")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
                        NSWorkspace.shared.open(downloadsDir)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Show in Finder")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            HStack {
                Text("Recent Activity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if downloadManager.hasActiveDownloads {
                    Text("\(downloadManager.activeDownloads.count) active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }

                if !downloadManager.items.isEmpty {
                    Button(action: {
                        downloadManager.clearFinished()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear List")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            if downloadManager.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("No Downloads")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Files downloaded from web pages will appear here.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            } else {
                SettingsCardGroup {
                    ForEach(Array(downloadManager.items.enumerated()), id: \.element.id) { index, item in
                        SettingsDownloadRowView(item: item, onRemove: {
                            downloadManager.removeItem(id: item.id)
                        })

                        if index < downloadManager.items.count - 1 {
                            SettingsDivider()
                        }
                    }
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

private struct SettingsHistoryRowView: View {
    let item: HistoryItem
    let onSelect: (_ inNewTab: Bool) -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var favicon: NSImage? = nil

    var body: some View {
        Button(action: {
            let inNewTab = NSEvent.modifierFlags.contains(.command)
            onSelect(inNewTab)
        }) {
            HStack(spacing: 12) {
                if let fav = favicon {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(item.host)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                Text(item.formattedTime)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
                .help("Delete from history")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            loadFavicon()
        }
        .contextMenu {
            Button("Open in Current Tab") {
                onSelect(false)
            }
            Button("Open in New Tab") {
                onSelect(true)
            }
            Divider()
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }
            Divider()
            Button("Delete from History", role: .destructive) {
                onDelete()
            }
        }
    }

    private func loadFavicon() {
        guard let host = URL(string: item.url)?.host, !host.isEmpty else { return }
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
        guard let url = faviconURL else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.favicon = img
            }
        }.resume()
    }
}

private struct SettingsDownloadRowView: View {
    @ObservedObject var item: DownloadItem
    let onRemove: () -> Void

    @State private var isHovered: Bool = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB, .useBytes, .useGB]
        return formatter
    }()

    private var fileIcon: NSImage {
        let ext = (item.suggestedFilename as NSString).pathExtension
        let icon: NSImage
        if let utType = UTType(filenameExtension: ext) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }
        icon.size = NSSize(width: 28, height: 28)
        return icon
    }

    private var progressSubtitle: String {
        switch item.status {
        case .downloading:
            if item.totalBytes > 0 {
                let current = Self.byteFormatter.string(fromByteCount: item.bytesDownloaded)
                let total = Self.byteFormatter.string(fromByteCount: item.totalBytes)
                let pct = Int(item.progress * 100)
                return "\(current) of \(total) (\(pct)%)"
            } else if item.bytesDownloaded > 0 {
                let current = Self.byteFormatter.string(fromByteCount: item.bytesDownloaded)
                return "\(current) downloaded"
            } else {
                return "Starting…"
            }
        case .completed:
            if item.totalBytes > 0 {
                let total = Self.byteFormatter.string(fromByteCount: item.totalBytes)
                return "\(total) · Complete"
            } else if let url = item.destinationURL,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? Int64 {
                let total = Self.byteFormatter.string(fromByteCount: size)
                return "\(total) · Complete"
            }
            return "Complete"
        case .failed(let err):
            return "Failed: \(err)"
        case .cancelled:
            return "Cancelled"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.suggestedFilename)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(progressSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(item.status == .downloading ? .secondary : (item.status == .completed ? .secondary : (item.status == .cancelled ? .secondary.opacity(0.8) : .red)))
                    .lineLimit(1)

                if item.status == .downloading {
                    ProgressView(value: item.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(height: 3)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 16)

            switch item.status {
            case .downloading:
                Button(action: {
                    item.cancel()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Cancel Download")

            case .completed:
                HStack(spacing: 8) {
                    if let url = item.destinationURL {
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                Text("Finder")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(isHovered ? 0.08 : 0.04))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")

                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 11))
                                Text("Open")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(isHovered ? 0.12 : 0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Open File")
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1.0 : 0.0)
                    .help("Remove from list")
                }

            case .failed, .cancelled:
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
                .help("Remove from list")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if let url = item.destinationURL {
                Button("Open File") {
                    NSWorkspace.shared.open(url)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                Divider()
            }
            Button("Remove from List", role: .destructive) {
                onRemove()
            }
        }
    }
}
