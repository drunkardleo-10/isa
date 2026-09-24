import SwiftUI
import AppKit
import Foundation

struct NewTabButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))

            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .background(NonDraggableBackground())
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .help("New Tab (⌘T)")
    }
}

struct NavButton: View {
    let icon: String
    let tooltip: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && !disabled ? Color.primary.opacity(0.08) : Color.clear)
                    .frame(width: 26, height: 26)

                NavSvgIcon(name: icon)
                    .foregroundColor(disabled ? .secondary.opacity(0.35) : (isHovered ? .primary : .secondary))
                    .frame(width: 15, height: 15)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

struct NavSvgIcon: View {
    let name: String

    var body: some View {
        if let img = AssetLoader.image(named: name) {
            Image(nsImage: img)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackSymbol
        }
    }

    @ViewBuilder
    private var fallbackSymbol: some View {
        switch name {
        case "back":
            Image(systemName: "chevron.backward")
                .font(.system(size: 12, weight: .medium))
        case "forward":
            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .medium))
        case "reload":
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
        case "home":
            Image(systemName: "house")
                .font(.system(size: 12, weight: .medium))
        default:
            EmptyView()
        }
    }
}

enum AssetLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let candidates: [URL] = [
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Assets"),
            Bundle.main.url(forResource: name, withExtension: "svg"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Assets/\(name).svg"),
            Bundle.main.bundleURL.appendingPathComponent("Assets/\(name).svg"),
            currentDir.appendingPathComponent("Assets/\(name).svg"),
            sourceDir.appendingPathComponent("Assets/\(name).svg")
        ].compactMap { $0 }

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                cache[name] = img
                return img
            }
        }
        return nil
    }
}
