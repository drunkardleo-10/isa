import Foundation
import WebKit
import Combine
import SwiftUI

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

    let webView: WKWebView

    var isNewTabState: Bool {
        currentURL == nil
    }

    init(url: URL? = nil) {
        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
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

    func toggleTheme() {
        theme = theme.next
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
    }

    func selectTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            selectedTabId = id
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
            withAnimation(.easeOut(duration: 0.2)) {
                tabs = [freshTab]
                selectedTabId = freshTab.id
            }
            bindTabs()
            return
        }

        if selectedTabId == id {
            let nextIndex = index < tabs.count - 1 ? index + 1 : index - 1
            selectedTabId = tabs[nextIndex].id
        }

        withAnimation(.easeOut(duration: 0.2)) {
            _ = tabs.remove(at: index)
        }
        bindTabs()
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
        withAnimation(.easeOut(duration: 0.2)) {
            tab.currentURL = url
            tab.addressText = url.absoluteString
            tab.isAddressOverlayPresented = false
        }
        tab.webView.load(URLRequest(url: url))
    }

    func reloadActiveTab() {
        activeTab.webView.reload()
    }

    func goBackActiveTab() {
        if activeTab.webView.canGoBack {
            activeTab.webView.goBack()
        }
    }

    func goForwardActiveTab() {
        if activeTab.webView.canGoForward {
            activeTab.webView.goForward()
        }
    }
}
