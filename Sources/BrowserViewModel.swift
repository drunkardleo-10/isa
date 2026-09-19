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

    let webView: WKWebView

    var isNewTabState: Bool {
        currentURL == nil
    }

    init(url: URL? = nil) {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.preferredContentMode = .desktop
        configuration.defaultWebpagePreferences = preferences
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if let url = url {
            self.addressText = url.absoluteString
            self.currentURL = url
            self.webView.load(URLRequest(url: url))
        }
    }
}

final class BrowserViewModel: ObservableObject {
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

    private var tabCancellables = Set<AnyCancellable>()

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
    }

    private func bindTabs() {
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
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func toggleTheme() {
        theme = theme.next
        applyAppAppearance()
        PerformanceMonitor.shared.log(event: "Theme", details: "Switched to \(theme.rawValue)")
    }

    func createNewTab(select: Bool = true) {
        let newTab = Tab()
        withAnimation(.easeOut(duration: 0.2)) {
            tabs.append(newTab)
            if select {
                selectedTabId = newTab.id
            }
        }
        bindTabs()
        PerformanceMonitor.shared.log(event: "Tab", details: "Created new tab \(newTab.id.uuidString.prefix(6)) (Total: \(tabs.count))")
    }

    func selectTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            selectedTabId = id
            let title = activeTab.pageTitle.isEmpty ? (activeTab.currentURL?.host ?? "New Tab") : activeTab.pageTitle
            PerformanceMonitor.shared.log(event: "Tab", details: "Selected tab \"\(title)\"")
        }
    }

    func selectTabNumber(_ number: Int) {
        guard !tabs.isEmpty else { return }
        if number == 9 && tabs.count < 9 {
            selectedTabId = tabs[tabs.count - 1].id
        } else {
            let index = number - 1
            if tabs.indices.contains(index) {
                selectedTabId = tabs[index].id
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
        bindTabs()
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

    func navigate(tab: Tab, to input: String) {
        guard let url = resolveURL(from: input) else { return }
        PerformanceMonitor.shared.log(event: "Navigation", details: "Navigating to \(url.absoluteString)")
        withAnimation(.easeOut(duration: 0.2)) {
            tab.currentURL = url
            tab.addressText = url.absoluteString
            tab.isAddressOverlayPresented = false
            tab.favicon = nil
        }
        tab.webView.load(URLRequest(url: url))
    }

    func reloadActiveTab() {
        PerformanceMonitor.shared.log(event: "Navigation", details: "Reloading active tab")
        activeTab.webView.reload()
    }

    func goBackActiveTab() {
        if activeTab.webView.canGoBack {
            PerformanceMonitor.shared.log(event: "Navigation", details: "Navigating back")
            activeTab.webView.goBack()
        }
    }

    func goForwardActiveTab() {
        if activeTab.webView.canGoForward {
            PerformanceMonitor.shared.log(event: "Navigation", details: "Navigating forward")
            activeTab.webView.goForward()
        }
    }
}
