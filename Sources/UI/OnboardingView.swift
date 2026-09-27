import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var page: Int = 0
    @State private var forward: Bool = true

    @State private var selectedSource: WebKitSourceType = .safari
    @State private var importBookmarks: Bool = true
    @State private var importHistory: Bool = true
    @State private var customSelectedFileURL: URL? = nil
    @State private var isImporting: Bool = false
    @State private var importResult: WebKitImportResult? = nil

    @State private var isDefaultBrowser: Bool = {
        guard let probe = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }()
    @State private var askedDefault: Bool = false

    private let totalPages = 4

    private var appLogo: NSImage? {
        if let img = NSImage(contentsOfFile: "Assets/AppIcon.icns") { return img }
        if let img = NSImage(contentsOfFile: "Assets/isa_browser.png") { return img }
        if let img = NSImage(contentsOfFile: "Assets/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png") { return img }
        if let img = NSImage(named: "AppIcon") { return img }
        if let bundlePath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: bundlePath) { return img }
        return nil
    }

    var body: some View {
        ZStack(alignment: .center) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {}

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    ZStack {
                        switch page {
                        case 0:
                            welcomePage
                        case 1:
                            importPage
                        case 2:
                            personalizePage
                        default:
                            readyPage
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? 32 : -32).combined(with: .opacity),
                        removal: .offset(x: forward ? -32 : 32).combined(with: .opacity)
                    ))

                    footerBar
                }

                Button(action: {
                    viewModel.completeOnboarding()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .padding(.trailing, 20)
                .help("Close")
            }
            .frame(width: 520, height: 460)
            .background(.ultraThinMaterial)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 32, x: 0, y: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: page)
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            if let logo = appLogo {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
            }

            VStack(spacing: 10) {
                Text("Welcome to isa")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("A browser with nothing in the way. Ultra lightweight, powered by the native WebKit engine already in your Mac, and designed to stay out of your sight.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }

    private var importPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bring Things Over")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Import bookmarks and browsing history directly from Safari and other native WebKit browsers.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Source Browser")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(WebKitSourceType.allCases.filter { $0.isDetected }) { source in
                        Button(action: {
                            selectedSource = source
                            importResult = nil
                        }) {
                            VStack(spacing: 5) {
                                Image(systemName: source.iconName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(selectedSource == source ? Color.accentColor : .primary)

                                Text(source.displayName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(selectedSource == source ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedSource == source ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(selectedSource == source ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if selectedSource == .file {
                HStack(spacing: 10) {
                    Button(action: {
                        WebKitImporter.shared.pickBookmarksFile { url in
                            if let url = url {
                                customSelectedFileURL = url
                                importResult = nil
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text(customSelectedFileURL != nil ? "Change File…" : "Select Bookmarks File…")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if let url = customSelectedFileURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(spacing: 6) {
                importToggleRow(
                    title: "Bookmarks & Favorites",
                    subtitle: "Folders, reading list, and menu items",
                    icon: "bookmark",
                    isOn: $importBookmarks
                )

                if selectedSource != .file {
                    importToggleRow(
                        title: "Browsing History",
                        subtitle: "Recent visits for quick address bar completion",
                        icon: "clock",
                        isOn: $importHistory
                    )
                }
            }

            HStack(spacing: 12) {
                Button(action: executeImport) {
                    HStack(spacing: 6) {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.doc")
                        }
                        Text(isImporting ? "Importing…" : "Import Selected Data")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isImporting || (!importBookmarks && !importHistory) || (selectedSource == .file && customSelectedFileURL == nil))

                if let result = importResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.bookmarksCount > 0 || result.historyCount > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(result.bookmarksCount > 0 || result.historyCount > 0 ? Color.green : Color.orange)

                        Text(result.message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let result = importResult, result.requiresPermissionPrompt {
                Button(action: {
                    WebKitImporter.shared.pickBookmarksFile { url in
                        if let url = url {
                            customSelectedFileURL = url
                            selectedSource = .file
                            executeImport()
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.badge.plus")
                        Text("Select Safari Bookmarks.plist or HTML File Manually")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    private func importToggleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func executeImport() {
        isImporting = true
        WebKitImporter.shared.performImport(
            source: selectedSource,
            selectedFileURL: customSelectedFileURL,
            importBookmarks: importBookmarks,
            importHistory: importHistory
        ) { result in
            self.isImporting = false
            self.importResult = result
        }
    }

    private var personalizePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make It Yours")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Configure your default search engine, appearance, and tab layout.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Default Search Engine")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(SearchEngine.allCases) { engine in
                        searchEngineButton(engine)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("Search with \(viewModel.searchEngine.displayName) or enter address")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.8))

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance Theme")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in
                        themeButton(theme)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tab Placement")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    tabPlacementCard(
                        placement: .top,
                        title: "Top Tab Strip",
                        subtitle: "Classic tabs across top",
                        icon: "menubar.rectangle"
                    )

                    tabPlacementCard(
                        placement: .left,
                        title: "Left Sidebar",
                        subtitle: "Modern vertical tabs",
                        icon: "sidebar.left"
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    private func searchEngineButton(_ engine: SearchEngine) -> some View {
        let isSelected = viewModel.searchEngine == engine
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.searchEngine = engine
            }
        }) {
            Text(engine.displayName)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func themeButton(_ theme: AppTheme) -> some View {
        let isSelected = viewModel.theme == theme
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.theme = theme
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: themeIcon(theme))
                Text(theme.displayName)
            }
            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func themeIcon(_ theme: AppTheme) -> String {
        switch theme {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private func tabPlacementCard(placement: TabPlacement, title: String, subtitle: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.tabPlacement = placement
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.tabPlacement == placement ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(viewModel.tabPlacement == placement ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(viewModel.tabPlacement == placement ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var readyPage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("You're All Set")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("isa is fast, minimal, and ready for you.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            if isDefaultBrowser {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("isa is your default web browser")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.08))
                .clipShape(Capsule())
            } else {
                Button(action: {
                    askedDefault = true
                    let app = Bundle.main.bundleURL
                    for scheme in ["http", "https"] {
                        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { _ in
                            DispatchQueue.main.async {
                                if let probe = URL(string: "https://example.com"),
                                   let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) {
                                    isDefaultBrowser = handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
                                }
                            }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "app.badge.checkmark")
                        Text("Make isa the Default Browser")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if askedDefault, !isDefaultBrowser {
                    Text("macOS will prompt to confirm default browser change")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("HELPFUL SHORTCUTS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    shortcutCard(key: "⌘T", label: "New tab")
                    shortcutCard(key: "⌘L", label: "Focus address bar")
                    shortcutCard(key: "⌘+ / ⌘-", label: "Native page zoom")
                    shortcutCard(key: "⌘F", label: "Find in page")
                    shortcutCard(key: "Two Fingers", label: "Swipe history")
                    shortcutCard(key: "Double Tap", label: "Smart zoom")
                }
            }
            .frame(maxWidth: 440)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }

    private func shortcutCard(key: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(5)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var footerBar: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                        .scaleEffect(i == page ? 1.2 : 1.0)
                        .onTapGesture {
                            forward = i > page
                            page = i
                        }
                }
            }

            Spacer()

            if page > 0 {
                Button("Back") {
                    forward = false
                    page -= 1
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
            }

            if page < totalPages - 1 {
                Button("Skip") {
                    viewModel.completeOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
            }

            Button(action: {
                if page < totalPages - 1 {
                    forward = true
                    page += 1
                } else {
                    viewModel.completeOnboarding()
                }
            }) {
                Text(page < totalPages - 1 ? "Continue" : "Start Browsing")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}
