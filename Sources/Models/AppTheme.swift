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

enum TabPlacement: String, CaseIterable, Identifiable {
    case top = "top"
    case left = "left"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top Bar"
        case .left: return "Left Sidebar"
        }
    }

    var iconName: String {
        switch self {
        case .top: return "macwindow"
        case .left: return "sidebar.left"
        }
    }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google = "google"
    case ecosia = "ecosia"
    case duckduckgo = "duckduckgo"
    case bing = "bing"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .ecosia: return "Ecosia"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .custom: return "Custom"
        }
    }

    static var current: SearchEngine {
        if let saved = UserDefaults.standard.string(forKey: "defaultSearchEngine"),
           let engine = SearchEngine(rawValue: saved) {
            return engine
        }
        return .google
    }

    func searchURL(for query: String, customTemplate: String = "") -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .ecosia:
            return URL(string: "https://www.ecosia.org/search?q=\(encoded)")
        case .duckduckgo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .custom:
            let template = customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if template.isEmpty {
                return URL(string: "https://www.google.com/search?q=\(encoded)")
            }
            if template.contains("%s") {
                return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
            } else if template.contains("%@") {
                return URL(string: template.replacingOccurrences(of: "%@", with: encoded))
            } else if template.hasSuffix("=") || template.hasSuffix("?") {
                return URL(string: template + encoded)
            } else {
                let separator = template.contains("?") ? "&q=" : "?q="
                return URL(string: template + separator + encoded)
            }
        }
    }
}
