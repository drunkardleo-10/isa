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
