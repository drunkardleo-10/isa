import Foundation
import Combine

struct BookmarkItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var url: String
    var folder: String?
    var dateAdded: Date = Date()

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return URL(string: url)?.host ?? url
    }
}

final class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()
    private let storageKey = "isa_bookmarks_v1"

    @Published var bookmarks: [BookmarkItem] = []

    init() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BookmarkItem].self, from: data) {
            self.bookmarks = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func add(title: String, url: String, folder: String? = nil) {
        let item = BookmarkItem(title: title, url: url, folder: folder)
        bookmarks.insert(item, at: 0)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func importItems(_ items: [BookmarkItem]) -> Int {
        var existing = Set(bookmarks.map { $0.url })
        var addedCount = 0
        for item in items {
            guard !existing.contains(item.url) else { continue }
            existing.insert(item.url)
            bookmarks.append(item)
            addedCount += 1
        }
        if addedCount > 0 {
            save()
        }
        return addedCount
    }
}
