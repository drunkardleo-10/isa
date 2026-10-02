import SwiftUI
import AppKit

enum SearchEngineAssets {
    private static var cache: [String: NSImage] = [:]

    static func image(for engine: SearchEngine) -> NSImage? {
        if let cached = cache[engine.rawValue] {
            return cached
        }
        let name = engine.rawValue
        let candidates: [URL] = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Assets/SearchEngines"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Assets/SearchEngines/\(name).png"),
            Bundle.main.bundleURL.appendingPathComponent("Assets/SearchEngines/\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/SearchEngines/\(name).png"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/SearchEngines/\(name).png")
        ].compactMap { $0 }

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url), img.isValid {
                cache[name] = img
                return img
            }
        }
        return nil
    }
}

struct SearchEngineLogoView: View {
    var engine: SearchEngine = .google
    var customURL: String = ""
    var size: CGFloat = 16
    @State private var loadedFavicon: NSImage? = nil

    var body: some View {
        Group {
            if engine == .custom {
                if let img = loadedFavicon {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.2), style: .continuous))
                } else {
                    fallbackSearchIcon
                }
            } else if let img = SearchEngineAssets.image(for: engine) ?? loadedFavicon {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.2), style: .continuous))
            } else {
                fallbackSearchIcon
            }
        }
        .onAppear {
            loadOnlineIfNeeded()
        }
        .onChange(of: customURL) { _, _ in
            loadOnlineIfNeeded()
        }
        .onChange(of: engine) { _, _ in
            loadOnlineIfNeeded()
        }
    }

    private var fallbackSearchIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: max(8, size * 0.75), weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: size, height: size)
    }

    private func loadOnlineIfNeeded() {
        if engine == .custom {
            let template = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !template.isEmpty else {
                loadedFavicon = nil
                return
            }
            if let cached = FaviconService.shared.cachedFavicon(for: template) {
                loadedFavicon = cached
                return
            }
            FaviconService.shared.loadFavicon(for: template) { img in
                self.loadedFavicon = img
            }
        } else if SearchEngineAssets.image(for: engine) == nil {
            let host: String
            switch engine {
            case .google: host = "google.com"
            case .duckduckgo: host = "duckduckgo.com"
            case .bing: host = "bing.com"
            case .ecosia: host = "ecosia.org"
            case .custom: return
            }
            FaviconService.shared.loadFavicon(for: host) { img in
                self.loadedFavicon = img
            }
        }
    }
}
