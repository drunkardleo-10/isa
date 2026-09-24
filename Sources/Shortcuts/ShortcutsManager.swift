import Foundation
import AppKit
import Combine
import CryptoKit

struct ShortcutItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: String

    init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

final class ShortcutsManager: ObservableObject {
    static let shared = ShortcutsManager()
    static let maxShortcuts = 6

    private let storageKey = "isa_shortcuts"
    @Published var shortcuts: [ShortcutItem] = []
    @Published var favicons: [UUID: NSImage] = [:]

    init() {
        loadShortcuts()
    }

    func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ShortcutItem].self, from: data) {
            self.shortcuts = decoded
        } else {
            self.shortcuts = [
                ShortcutItem(title: "X", url: "https://x.com"),
                ShortcutItem(title: "github", url: "https://github.com"),
                ShortcutItem(title: "Adblocker", url: "https://adblock.turtlecute.org/")
            ]
            saveShortcuts()
        }

        for item in shortcuts {
            fetchFavicon(for: item)
        }
    }

    func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.synchronize()
        }
    }

    @discardableResult
    func addShortcut(title: String, url: String) -> Bool {
        guard shortcuts.count < Self.maxShortcuts else { return false }
        let normalizedURL = normalizeURL(url)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (URL(string: normalizedURL)?.host ?? "Site")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = ShortcutItem(title: normalizedTitle, url: normalizedURL)
        shortcuts.append(item)
        saveShortcuts()
        fetchFavicon(for: item)
        return true
    }

    func updateShortcut(id: UUID, title: String, url: String) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let normalizedURL = normalizeURL(url)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (URL(string: normalizedURL)?.host ?? "Site")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        shortcuts[index].title = normalizedTitle
        shortcuts[index].url = normalizedURL
        saveShortcuts()
        favicons.removeValue(forKey: id)
        fetchFavicon(for: shortcuts[index])
    }

    func removeShortcut(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        favicons.removeValue(forKey: id)
        saveShortcuts()
    }

    func normalizeURL(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }

    func fetchFavicon(for item: ShortcutItem) {
        guard let url = URL(string: item.url), let host = url.host, !host.isEmpty else { return }
        let rootHost = extractRootHost(from: host)

        var candidateURLs: [URL] = []

        if let direct = URL(string: "https://\(host)/favicon.ico") {
            candidateURLs.append(direct)
        }
        if rootHost != host, let directRoot = URL(string: "https://\(rootHost)/favicon.ico") {
            candidateURLs.append(directRoot)
        }
        if let ddgHost = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            candidateURLs.append(ddgHost)
        }
        if rootHost != host, let ddgRoot = URL(string: "https://icons.duckduckgo.com/ip3/\(rootHost).ico") {
            candidateURLs.append(ddgRoot)
        }
        if let googleHost = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
            candidateURLs.append(googleHost)
        }
        if rootHost != host, let googleRoot = URL(string: "https://www.google.com/s2/favicons?domain=\(rootHost)&sz=64") {
            candidateURLs.append(googleRoot)
        }

        tryFetchFavicon(from: candidateURLs, for: item.id)
    }

    private func tryFetchFavicon(from candidates: [URL], for itemId: UUID) {
        guard !candidates.isEmpty else { return }
        var remaining = candidates
        let currentURL = remaining.removeFirst()

        var request = URLRequest(url: currentURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data = data, !data.isEmpty,
               !self.isFallbackGlobe(data: data),
               let image = NSImage(data: data),
               image.isValid, image.size.width > 1 && image.size.height > 1 {
                DispatchQueue.main.async {
                    self.favicons[itemId] = image
                }
            } else {
                self.tryFetchFavicon(from: remaining, for: itemId)
            }
        }.resume()
    }

    private func isFallbackGlobe(data: Data) -> Bool {
        if data.count == 726 { return true }
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
        return md5 == "b8a0bf372c762e966cc99ede8682bc71"
    }

    private func extractRootHost(from host: String) -> String {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        guard parts.count > 2 else { return host }
        let specialTLDs = ["co.uk", "com.au", "co.in", "com.br", "co.nz", "co.jp", "com.sg"]
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if specialTLDs.contains(lastTwo) && parts.count > 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}
