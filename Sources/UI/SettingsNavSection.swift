import SwiftUI

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
