import Foundation
import AppKit
import Combine

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
                ShortcutItem(title: "GitHub", url: "https://github.com"),
                ShortcutItem(title: "YouTube", url: "https://youtube.com"),
                ShortcutItem(title: "Reddit", url: "https://reddit.com"),
                ShortcutItem(title: "Wikipedia", url: "https://wikipedia.org")
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
        guard let iconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") else { return }

        URLSession.shared.dataTask(with: iconURL) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.favicons[item.id] = image
            }
        }.resume()
    }
}
