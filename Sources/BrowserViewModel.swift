import Foundation
import WebKit
import Combine
import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var next: AppTheme {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }
}

final class Tab: Identifiable, ObservableObject {
    let id: UUID = UUID()
    @Published var addressText: String = ""
    @Published var currentURL: URL? = nil
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isAddressOverlayPresented: Bool = false
    @Published var favicon: NSImage? = nil

    @Published var webView: WKWebView? = nil
    @Published var snapshotImage: NSImage? = nil
    @Published var isSleeping: Bool = false
    @Published var isSnapshotting: Bool = false
    var lastActiveTime: Date = Date()

    var isNewTabState: Bool {
        currentURL == nil
    }

    @discardableResult
    func ensureWebView(caller: String = #function) -> WKWebView {
        if let existing = webView {
            return existing
        }
        PerformanceMonitor.shared.log(event: "WebKitInit", details: "Instantiating WKWebView for tab \(id.uuidString.prefix(6)) from [\(caller)]")
        let configuration = WKWebViewConfiguration()
        configuration.processPool = BrowserViewModel.sharedProcessPool
        let preferences = WKWebpagePreferences()
        preferences.preferredContentMode = .desktop
        configuration.defaultWebpagePreferences = preferences
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        self.webView = newWebView
        return newWebView
    }

    init(url: URL? = nil, lazy: Bool = false) {
        PerformanceMonitor.shared.log(event: "TabInit", details: "Tab \(id.uuidString.prefix(6)) initialized (url: \(url?.absoluteString ?? "nil")) | webView is \(url != nil && !lazy ? "eager" : "NIL")")
        if let url = url {
            self.addressText = url.absoluteString
            self.currentURL = url
            self.pageTitle = url.host ?? ""
            if !lazy {
                let wv = ensureWebView(caller: "Tab.init(url:)")
                wv.load(URLRequest(url: url))
            } else {
                self.isSleeping = true
            }
        }
    }
}

final class BrowserViewModel: ObservableObject {
    static let sharedProcessPool = WKProcessPool()

    @Published var tabs: [Tab] = []
    @Published var selectedTabId: UUID = UUID()
    @Published var theme: AppTheme = {
        if let saved = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: saved) {
            return theme
        }
        return .system
    }() {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        }
    }
    @Published var isBenchmarkRunning: Bool = false
    private var tabCancellables = Set<AnyCancellable>()
    private var sleepMaintenanceTimer: Timer?
    private let sleepTimeoutInterval: TimeInterval = 600 
    private let tabThresholdForSleep: Int = 6 

    var activeTab: Tab {
        if let tab = tabs.first(where: { $0.id == selectedTabId }) {
            return tab
        }
        if let first = tabs.first {
            return first
        }
        let fallback = Tab()
        tabs = [fallback]
        selectedTabId = fallback.id
        bindTabs()
        return fallback
    }

    init() {
        let initialTab = Tab()
        self.tabs = [initialTab]
        self.selectedTabId = initialTab.id
        bindTabs()
        applyAppAppearance()
        PerformanceMonitor.shared.startPeriodicLogging { [weak self] in
            self?.tabs.count ?? 0
        }
        PerformanceMonitor.shared.log(event: "Launch", details: "Initial tab created (theme: \(theme.rawValue))")

        sleepMaintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkTabSleeping()
        }
    }

    func bindTabs() {
        tabCancellables.removeAll()
        for tab in tabs {
            tab.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &tabCancellables)
        }
    }

    func applyAppAppearance() {
        guard let app = NSApp else { return }
        switch theme {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func toggleTheme() {
        theme = theme.next
        applyAppAppearance()
        PerformanceMonitor.shared.log(event: "Theme", details: "Switched to \(theme.rawValue)")
    }

    func createNewTab(select: Bool = true) {
        if select {
            activeTab.lastActiveTime = Date()
        }
        let newTab = Tab()
        withAnimation(.easeOut(duration: 0.2)) {
            tabs.append(newTab)
            if select {
                selectedTabId = newTab.id
            }
        }
        bindTabs()
        PerformanceMonitor.shared.log(event: "Tab", details: "Created new tab \(newTab.id.uuidString.prefix(6)) (Total: \(tabs.count)) | webView: \(newTab.webView != nil ? "INSTANTIATED" : "nil")")
        checkTabSleeping()
    }

    func selectTab(id: UUID) {
        guard let targetTab = tabs.first(where: { $0.id == id }) else { return }
        if targetTab.id != selectedTabId {
            activeTab.lastActiveTime = Date()
            selectedTabId = id
            wakeTabIfNeeded(targetTab)
            checkTabSleeping()
            let title = activeTab.pageTitle.isEmpty ? (activeTab.currentURL?.host ?? "New Tab") : activeTab.pageTitle
            PerformanceMonitor.shared.log(event: "Tab", details: "Selected tab \"\(title)\"")
        }
    }

    func selectTabNumber(_ number: Int) {
        guard !tabs.isEmpty else { return }
        if number == 9 && tabs.count < 9 {
            selectTab(id: tabs[tabs.count - 1].id)
        } else {
            let index = number - 1
            if tabs.indices.contains(index) {
                selectTab(id: tabs[index].id)
            }
        }
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs.count == 1 {
            let freshTab = Tab()
            withAnimation(.easeInOut(duration: 0.2)) {
                tabs = [freshTab]
                selectedTabId = freshTab.id
            }
            bindTabs()
            PerformanceMonitor.shared.log(event: "Tab", details: "Closed last tab, reset to fresh tab")
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedTabId == id {
                let nextIndex = index < tabs.count - 1 ? index + 1 : index - 1
                selectedTabId = tabs[nextIndex].id
                wakeTabIfNeeded(activeTab)
            }
            _ = tabs.remove(at: index)
        }
        bindTabs()
        PerformanceMonitor.shared.log(event: "Tab", details: "Closed tab at index [\(index)] (Remaining: \(tabs.count))")
    }

    func closeActiveTab() {
        closeTab(id: selectedTabId)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              tabs.indices.contains(destinationIndex) else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
        PerformanceMonitor.shared.log(event: "Tab", details: "Dragged tab from [\(sourceIndex)] to [\(destinationIndex)]")
    }

    func focusAddressBar() {
        activeTab.addressText = activeTab.currentURL?.absoluteString ?? ""
        withAnimation(.easeOut(duration: 0.2)) {
            activeTab.isAddressOverlayPresented = true
        }
    }

    func dismissAddressBar() {
        withAnimation(.easeOut(duration: 0.2)) {
            activeTab.isAddressOverlayPresented = false
        }
    }

    func openSampleTabs(count: Int = 25, delayPerTab: TimeInterval = 3.0, onComplete: (() -> Void)? = nil) {
        guard !isBenchmarkRunning else { return }
        isBenchmarkRunning = true

        let websites: [(title: String, url: String)] = [
            ("Wikipedia", "https://www.wikipedia.org/?utm_source=chatgpt.com"),
            ("GitHub", "https://github.com/?utm_source=chatgpt.com"),
            ("YouTube", "https://www.youtube.com/?utm_source=chatgpt.com"),
            ("Reddit", "https://www.reddit.com/?utm_source=chatgpt.com"),
            ("Google Maps", "https://maps.google.com/?utm_source=chatgpt.com"),
            ("Figma", "https://www.figma.com/?utm_source=chatgpt.com"),
            ("Discord", "https://discord.com/app?utm_source=chatgpt.com"),
            ("Twitch", "https://www.twitch.tv/?utm_source=chatgpt.com"),
            ("WebGL Samples", "https://webglsamples.org/?utm_source=chatgpt.com"),
            ("Three.js Examples", "https://threejs.org/examples/?utm_source=chatgpt.com"),
            ("Apple", "https://www.apple.com/?utm_source=chatgpt.com"),
            ("Hacker News", "https://news.ycombinator.com/?utm_source=chatgpt.com"),
            ("MDN Web Docs", "https://developer.mozilla.org/?utm_source=chatgpt.com"),
            ("Stack Overflow", "https://stackoverflow.com/?utm_source=chatgpt.com"),
            ("BBC News", "https://www.bbc.com/?utm_source=chatgpt.com"),
            ("CNN", "https://www.cnn.com/?utm_source=chatgpt.com"),
            ("Amazon", "https://www.amazon.com/?utm_source=chatgpt.com"),
            ("X", "https://x.com/?utm_source=chatgpt.com"),
            ("LinkedIn", "https://www.linkedin.com/?utm_source=chatgpt.com"),
            ("Spotify", "https://open.spotify.com/?utm_source=chatgpt.com"),
            ("DuckDuckGo", "https://duckduckgo.com/?utm_source=chatgpt.com"),
            ("Swift", "https://www.swift.org/?utm_source=chatgpt.com"),
            ("Vercel", "https://vercel.com/?utm_source=chatgpt.com"),
            ("Cloudflare", "https://www.cloudflare.com/?utm_source=chatgpt.com"),
            ("OpenAI", "https://openai.com/?utm_source=chatgpt.com")
        ]

        let targetSites = Array(websites.prefix(count))
        var index = 0

        func loadStep() {
            guard index < targetSites.count else {
                self.isBenchmarkRunning = false
                PerformanceMonitor.shared.log(event: "BenchmarkComplete", details: "All \(targetSites.count) benchmark tabs loaded (Total: \(self.tabs.count))")
                onComplete?()
                return
            }

            let item = targetSites[index]
            PerformanceMonitor.shared.log(event: "BenchmarkStep", details: "[\(index + 1)/\(targetSites.count)] Opening and loading \(item.title) (\(item.url))")

            let targetTab: Tab
            if index == 0, let first = self.tabs.first, first.isNewTabState {
                targetTab = first
            } else {
                let tab = Tab()
                withAnimation(.easeOut(duration: 0.2)) {
                    self.tabs.append(tab)
                    self.selectedTabId = tab.id
                }
                self.bindTabs()
                targetTab = tab
            }

            targetTab.pageTitle = item.title
            self.selectedTabId = targetTab.id
            self.navigate(tab: targetTab, to: item.url)
            if let host = URL(string: item.url)?.host {
                self.loadFavicon(for: targetTab, host: host)
            }

            index += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delayPerTab) { [weak self] in
                guard self != nil else { return }
                loadStep()
            }
        }

        loadStep()
    }

    func loadFavicon(for tab: Tab, host: String) {
        guard let iconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") else { return }
        URLSession.shared.dataTask(with: iconURL) { [weak tab] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                tab?.favicon = image
            }
        }.resume()
    }

    func resolveURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }

        let domainPattern = "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(/.*)?$"
        if trimmed.range(of: domainPattern, options: .regularExpression) != nil {
            return URL(string: "https://" + trimmed)
        }

        if trimmed.hasPrefix("localhost:") || trimmed == "localhost" {
            return URL(string: "http://" + trimmed)
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }

    func isDirectURL(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return true
        }
        let domainPattern = "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(/.*)?$"
        if trimmed.range(of: domainPattern, options: .regularExpression) != nil {
            return true
        }
        if trimmed.hasPrefix("localhost:") || trimmed == "localhost" {
            return true
        }
        return false
    }

    func navigate(tab: Tab, to input: String) {
        guard let url = resolveURL(from: input) else { return }
        PerformanceMonitor.shared.log(event: "Navigation", details: "Navigating to \(url.absoluteString)")
        tab.lastActiveTime = Date()
        tab.isSleeping = false
        let webView = tab.ensureWebView()
        withAnimation(.easeOut(duration: 0.2)) {
            tab.currentURL = url
            tab.addressText = url.absoluteString
            tab.isAddressOverlayPresented = false
            tab.favicon = nil
        }
        webView.load(URLRequest(url: url))
    }

    func reloadActiveTab() {
        guard let webView = activeTab.webView else { return }
        PerformanceMonitor.shared.log(event: "Navigation", details: "Reloading active tab")
        activeTab.lastActiveTime = Date()
        webView.reload()
    }

    func goBackActiveTab() {
        guard let webView = activeTab.webView, webView.canGoBack else { return }
        PerformanceMonitor.shared.log(event: "Navigation", details: "Navigating back")
        activeTab.lastActiveTime = Date()
        webView.goBack()
    }

    func goForwardActiveTab() {
        guard let webView = activeTab.webView, webView.canGoForward else { return }
        PerformanceMonitor.shared.log(event: "Navigation", details: "Navigating forward")
        activeTab.lastActiveTime = Date()
        webView.goForward()
    }

    

    
    
    
    func sleepTab(_ tab: Tab) {
        guard tab.id != selectedTabId,
              !tab.isSleeping,
              !tab.isSnapshotting,
              let webView = tab.webView,
              !tab.isLoading,
              tab.currentURL != nil else {
            return
        }

        tab.isSnapshotting = true
        webView.takeSnapshot(with: nil) { [weak self, weak tab] image, error in
            DispatchQueue.main.async {
                guard let self = self, let tab = tab else { return }
                tab.isSnapshotting = false

                
                guard tab.id != self.selectedTabId else { return }

                tab.snapshotImage = image
                tab.isSleeping = true
                
                tab.webView = nil
                let title = tab.pageTitle.isEmpty ? (tab.currentURL?.host ?? "Tab") : tab.pageTitle
                PerformanceMonitor.shared.log(event: "Sleep", details: "Tab \"\(title)\" put to sleep")
            }
        }
    }

    func wakeTabIfNeeded(_ tab: Tab) {
        tab.lastActiveTime = Date()
        guard tab.isSleeping else { return }

        let title = tab.pageTitle.isEmpty ? (tab.currentURL?.host ?? "Tab") : tab.pageTitle
        PerformanceMonitor.shared.log(event: "Wake", details: "Waking tab \"\(title)\"")
        tab.isSleeping = false
        let webView = tab.ensureWebView()
        if let url = tab.currentURL {
            webView.load(URLRequest(url: url))
        }
    }

    func checkTabSleeping() {
        if isBenchmarkRunning { return }
        let now = Date()
        let backgroundTabs = tabs.filter {
            $0.id != selectedTabId &&
            $0.webView != nil &&
            !$0.isSleeping &&
            !$0.isSnapshotting &&
            !$0.isLoading &&
            $0.currentURL != nil
        }

        
        for tab in backgroundTabs {
            if now.timeIntervalSince(tab.lastActiveTime) >= sleepTimeoutInterval {
                sleepTab(tab)
            }
        }

        
        if tabs.count >= tabThresholdForSleep {
            let eligible = backgroundTabs
                .sorted { $0.lastActiveTime < $1.lastActiveTime }
            for tab in eligible {
                let activeLiveCount = tabs.filter { $0.webView != nil }.count
                if activeLiveCount >= tabThresholdForSleep {
                    sleepTab(tab)
                }
            }
        }
    }
}
