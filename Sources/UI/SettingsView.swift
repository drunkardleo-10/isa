import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject private var historyManager: HistoryManager = HistoryManager.shared
    @ObservedObject private var downloadManager: DownloadManager = DownloadManager.shared
    @State private var selectedSection: SettingsNavSection = .general
    @State private var hoveredSection: SettingsNavSection? = nil
    @ObservedObject private var updater: Updater = Updater.shared
    @State private var historySearchText: String = ""
    @State private var showClearBrowsingDataSheet: Bool = false
    @State private var contentAppeared: Bool = false
    @FocusState private var searchFocused: Bool
    @Namespace private var navNamespace
    @Namespace private var themeNamespace
    @Namespace private var tabNamespace

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
                    headerView

                    Group {
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
                    }
                    .id("settings-content-\(selectedSection.rawValue)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 10)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showClearBrowsingDataSheet) {
            ClearBrowsingDataSheet(historyManager: historyManager, isPresented: $showClearBrowsingDataSheet)
        }
        .onAppear {
            syncSectionWithURL()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                contentAppeared = true
            }
        }
        .onChange(of: viewModel.activeTab.currentURL) { _, _ in
            syncSectionWithURL()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selectedSection)
    }

    private func syncSectionWithURL() {
        guard let url = viewModel.activeTab.currentURL, url.scheme?.lowercased() == "isa" else { return }
        let host = url.host?.lowercased() ?? ""
        let target: SettingsNavSection?
        if host == "history" {
            target = .history
        } else if host == "downloads" {
            target = .downloads
        } else if host == "appearance" {
            target = .appearance
        } else if host == "browsing" {
            target = .browsing
        } else if host == "general" || host == "settings" {
            target = .general
        } else {
            target = nil
        }
        if let target, target != selectedSection {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedSection = target
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(selectedSection.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.primary)
                .id("title-\(selectedSection.rawValue)")
                .transition(.opacity.combined(with: .move(edge: .top)))

            Text(selectedSection.subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .id("subtitle-\(selectedSection.rawValue)")
                .transition(.opacity)
        }
        .padding(.bottom, 4)
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
                        namespace: navNamespace,
                        onSelect: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                selectedSection = section
                            }
                        },
                        onHover: { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                if hovering {
                                    hoveredSection = section
                                } else if hoveredSection == section {
                                    hoveredSection = nil
                                }
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
                    SettingsSwitch(isOn: $viewModel.isZenModeEnabled, label: "Zen mode")
                }
            }

            SettingsCardGroup {
                SettingsRow(
                    title: "Automatically check for updates",
                    subtitle: "isa checks for updates in the background and prepares them silently."
                ) {
                    SettingsSwitch(isOn: $viewModel.automaticallyCheckForUpdates, label: "Automatically check for updates")
                }

                SettingsDivider()

                SettingsRow(
                    title: versionTitle,
                    subtitle: versionDetail
                ) {
                    versionControl
                }
            }
        }
    }

    private var versionTitle: String {
        switch updater.stage {
        case .none:
            return "isa v1.0.0"
        case .fetching(let next):
            return "isa v\(next.version) is downloading…"
        case .ready(let next):
            return "isa v\(next.version) is ready"
        case .offered(let next), .waiting(let next):
            return "isa v\(next.version) is out"
        }
    }

    private var versionDetail: String {
        switch updater.stage {
        case .none:
            if let last = updater.lastChecked {
                return "Checked \(last.formatted(.relative(presentation: .named))) · Up to date"
            }
            return "Up to date · Checked once a day on its own"
        case .fetching(let next):
            return next.notes ?? "Downloading update in the background…"
        case .ready(let next):
            return next.notes ?? "Update downloaded. Ready to use on next launch."
        case .offered(let next):
            return next.notes ?? "Download the disk image to update manually."
        case .waiting(let next):
            return next.notes ?? "A new update is available."
        }
    }

    @ViewBuilder
    private var versionControl: some View {
        switch updater.stage {
        case .none:
            Button(action: {
                updater.check()
            }) {
                HStack(spacing: 5) {
                    if updater.checking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    }
                    Text(updater.checking ? "Checking..." : "Check Now")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(updater.checking ? 0.05 : 0.08))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .scaleEffect(updater.checking ? 0.97 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: updater.checking)
            }
            .buttonStyle(SettingsPressableButtonStyle())
            .disabled(updater.checking)

        case .fetching:
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Downloading…")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

        case .ready:
            Button(action: {
                updater.relaunch()
            }) {
                Text("Relaunch Now")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(SettingsPressableButtonStyle())

        case .offered(let next):
            Button(action: {
                NSWorkspace.shared.open(next.dmg)
            }) {
                Text("Download DMG")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(SettingsPressableButtonStyle())

        case .waiting:
            Button(action: {
                updater.install()
            }) {
                Text("Install Update")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(SettingsPressableButtonStyle())
        }
    }

    private var appearanceSectionView: some View {
        VStack(spacing: 16) {
            SettingsCardGroup {
                SettingsRow(
                    title: "Theme mode",
                    subtitle: "Select your preferred color scheme or follow your macOS system preference."
                ) {
                    SettingsPillPicker(
                        options: AppTheme.allCases,
                        selection: Binding(
                            get: { viewModel.theme },
                            set: { newTheme in
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                    viewModel.theme = newTheme
                                    viewModel.applyAppAppearance()
                                }
                                PerformanceMonitor.shared.log(event: "Theme", details: "Settings picker changed theme to \(newTheme.rawValue)")
                            }
                        ),
                        namespace: themeNamespace,
                        pillID: "themePill",
                        title: { theme in
                            switch theme {
                            case .system: return "System"
                            case .light: return "Light"
                            case .dark: return "Dark"
                            }
                        },
                        icon: { $0.iconName }
                    )
                    .frame(maxWidth: 270)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Tab layout",
                    subtitle: "Choose whether tabs and navigation appear along the top bar or in an elegant left sidebar."
                ) {
                    SettingsPillPicker(
                        options: TabPlacement.allCases,
                        selection: $viewModel.tabPlacement,
                        namespace: tabNamespace,
                        pillID: "tabPill",
                        title: { $0.displayName },
                        icon: { $0.iconName }
                    )
                    .frame(maxWidth: 270)
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
                    SettingsSwitch(isOn: $viewModel.isAdBlockEnabled, label: "Block Ads and Trackers")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Protection status",
                    subtitle: "\(formattedNet) network rules · \(formattedCos) cosmetic selectors"
                ) {
                    HStack(spacing: 6) {
                        PulsingDot(color: .green, isActive: viewModel.isAdBlockEnabled)

                        Text(viewModel.isAdBlockEnabled ? "Active" : "Paused")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(viewModel.isAdBlockEnabled ? .green : .secondary)
                            .contentTransition(.opacity)
                            .id(viewModel.isAdBlockEnabled ? "active" : "paused")
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.isAdBlockEnabled)
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
                        .focused($searchFocused)

                    if !historySearchText.isEmpty {
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                historySearchText = ""
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(SettingsPressableButtonStyle(pressedScale: 0.9))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(searchFocused ? 0.06 : 0.045))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(searchFocused ? 0.18 : 0.09), lineWidth: searchFocused ? 1.0 : 0.5)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: searchFocused)
                )
                .animation(.easeOut(duration: 0.18), value: searchFocused)

                Spacer()

                Text("\(filteredHistoryItems.count) visits")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                    .contentTransition(.numericText(countsDown: false))
                    .id(filteredHistoryItems.count)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: filteredHistoryItems.count)

                SettingsActionPill(
                    title: "Clear Data...",
                    systemImage: "trash",
                    tone: .destructive,
                    isEnabled: !historyManager.historyItems.isEmpty
                ) {
                    showClearBrowsingDataSheet = true
                }
            }
            .padding(.bottom, 4)

            if historyManager.historyItems.isEmpty {
                historyEmptyState(icon: "clock.arrow.circlepath", title: "No Browsing History", subtitle: "Websites you visit will appear here.")
            } else if filteredHistoryItems.isEmpty {
                historyEmptyState(icon: "magnifyingglass", title: "No Results Found", subtitle: "No history matching \"\(historySearchText)\"")
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
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                historyManager.deleteItem(id: item.id)
                                            }
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

    private func historyEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.35))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            Text(subtitle)
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
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
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

                    SettingsActionPill(title: "Show in Finder", systemImage: "folder") {
                        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
                        NSWorkspace.shared.open(downloadsDir)
                    }
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
                        .transition(.scale.combined(with: .opacity))
                }

                if !downloadManager.items.isEmpty {
                    SettingsActionPill(title: "Clear List", systemImage: "trash") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            downloadManager.clearFinished()
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: downloadManager.hasActiveDownloads)

            if downloadManager.items.isEmpty {
                historyEmptyState(icon: "arrow.down.circle", title: "No Downloads", subtitle: "Files downloaded from web pages will appear here.")
            } else {
                SettingsCardGroup {
                    ForEach(Array(downloadManager.items.enumerated()), id: \.element.id) { index, item in
                        SettingsDownloadRowView(item: item, onRemove: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                downloadManager.removeItem(id: item.id)
                            }
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


private struct SettingsHistoryRowView: View {
    let item: HistoryItem
    let onSelect: (_ inNewTab: Bool) -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var favicon: NSImage? = nil

    var body: some View {
        Button(action: {
            let inNewTab = NSEvent.modifierFlags.contains(.command)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                onSelect(inNewTab)
            }
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

                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        onDelete()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                        )
                }
                .buttonStyle(SettingsPressableButtonStyle(pressedScale: 0.85))
                .opacity(isHovered ? 1.0 : 0.0)
                .scaleEffect(isHovered ? 1.0 : 0.8)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
                .help("Delete from history")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
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
                withAnimation(.easeOut(duration: 0.25)) {
                    self.favicon = img
                }
            }
        }.resume()
    }
}

private struct SettingsDownloadRowView: View {
    @ObservedObject var item: DownloadItem
    let onRemove: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

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
                    .contentTransition(.opacity)
                    .id(progressSubtitle)

                if item.status == .downloading {
                    ProgressView(value: item.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(height: 3)
                        .padding(.top, 1)
                        .animation(.easeOut(duration: 0.25), value: item.progress)
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
                .buttonStyle(SettingsPressableButtonStyle(pressedScale: 0.88))
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
                        .buttonStyle(SettingsPressableButtonStyle())
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
                        .buttonStyle(SettingsPressableButtonStyle())
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
                    .buttonStyle(SettingsPressableButtonStyle(pressedScale: 0.85))
                    .opacity(isHovered ? 1.0 : 0.0)
                    .scaleEffect(isHovered ? 1.0 : 0.8)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
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
                .buttonStyle(SettingsPressableButtonStyle(pressedScale: 0.85))
                .opacity(isHovered ? 1.0 : 0.0)
                .scaleEffect(isHovered ? 1.0 : 0.8)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
                .help("Remove from list")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .scaleEffect(isPressed ? 0.99 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
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
