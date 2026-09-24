import Foundation
import AppKit
import Combine

enum ClearHistoryRange: String, CaseIterable, Identifiable {
    case lastHour = "Past Hour"
    case today = "Today"
    case allTime = "All Time"

    var id: String { rawValue }
}

struct HistoryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var url: String
    var title: String
    var visitTime: Date

    var host: String {
        URL(string: url)?.host ?? url
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return host.isEmpty ? url : host
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: visitTime)
    }
}

struct SuggestionItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let query: String
    let fullURL: String
    let isRecentSearch: Bool
    var isHistoryVisit: Bool = false

    var displayURL: String {
        if isHistoryVisit, let u = URL(string: fullURL) {
            return u.host ?? fullURL
        }
        return query
    }
    var displayTitle: String {
        if isHistoryVisit {
            return query
        }
        return isRecentSearch ? "Search history" : ""
    }
    var isSearch: Bool { !isHistoryVisit }
}

final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    private let searchHistoryKey = "searchHistory"
    private let browsingHistoryKey = "isa_browsing_history_v1"
    private let maxHistoryItems = 3000

    @Published var historyItems: [HistoryItem] = []
    @Published var searchQueries: [String] = []

    init() {
        loadHistory()
        if let saved = UserDefaults.standard.stringArray(forKey: searchHistoryKey) {
            self.searchQueries = saved
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: browsingHistoryKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.historyItems = decoded
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(historyItems) {
            UserDefaults.standard.set(data, forKey: browsingHistoryKey)
        }
    }

    func recordVisit(url: URL, title: String) {
        let urlString = url.absoluteString
        guard !urlString.isEmpty,
              urlString != "about:blank",
              !urlString.hasPrefix("data:"),
              url.scheme?.lowercased() != "isa",
              !url.isFileURL else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? (url.host ?? urlString) : cleanTitle

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Deduplicate rapid consecutive visits to the exact same URL within 15 seconds
            if let first = self.historyItems.first, first.url == urlString,
               abs(first.visitTime.timeIntervalSinceNow) < 15.0 {
                if self.historyItems[0].title.isEmpty || self.historyItems[0].title == url.host {
                    self.historyItems[0].title = resolvedTitle
                    self.saveHistory()
                }
                return
            }

            let item = HistoryItem(url: urlString, title: resolvedTitle, visitTime: Date())
            self.historyItems.insert(item, at: 0)

            if self.historyItems.count > self.maxHistoryItems {
                self.historyItems = Array(self.historyItems.prefix(self.maxHistoryItems))
            }
            self.saveHistory()
        }
    }

    func updateTitle(for url: URL, title: String) {
        let urlString = url.absoluteString
        guard !urlString.isEmpty, url.scheme?.lowercased() != "isa" else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.historyItems.firstIndex(where: { $0.url == urlString && abs($0.visitTime.timeIntervalSinceNow) < 300 }) {
                if self.historyItems[idx].title != cleanTitle {
                    self.historyItems[idx].title = cleanTitle
                    self.saveHistory()
                }
            }
        }
    }

    func deleteItem(id: UUID) {
        historyItems.removeAll { $0.id == id }
        saveHistory()
    }

    func deleteItems(ids: Set<UUID>) {
        historyItems.removeAll { ids.contains($0.id) }
        saveHistory()
    }

    func clearHistory(range: ClearHistoryRange) {
        let now = Date()
        switch range {
        case .lastHour:
            let cutoff = now.addingTimeInterval(-3600)
            historyItems.removeAll { $0.visitTime >= cutoff }
        case .today:
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: now)
            historyItems.removeAll { $0.visitTime >= startOfDay }
        case .allTime:
            historyItems.removeAll()
            searchQueries.removeAll()
            UserDefaults.standard.removeObject(forKey: searchHistoryKey)
        }
        saveHistory()
    }

    func clearAllHistory() {
        clearHistory(range: .allTime)
    }

    func search(query: String) -> [HistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return historyItems }
        return historyItems.filter {
            $0.title.lowercased().contains(trimmed) || $0.url.lowercased().contains(trimmed)
        }
    }

    func groupedHistory(for items: [HistoryItem]) -> [(String, [HistoryItem])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday.addingTimeInterval(-86400)
        let startOf7Days = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday.addingTimeInterval(-7 * 86400)
        let startOf30Days = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday.addingTimeInterval(-30 * 86400)

        var today: [HistoryItem] = []
        var yesterday: [HistoryItem] = []
        var past7Days: [HistoryItem] = []
        var past30Days: [HistoryItem] = []
        var older: [HistoryItem] = []

        for item in items {
            if item.visitTime >= startOfToday {
                today.append(item)
            } else if item.visitTime >= startOfYesterday {
                yesterday.append(item)
            } else if item.visitTime >= startOf7Days {
                past7Days.append(item)
            } else if item.visitTime >= startOf30Days {
                past30Days.append(item)
            } else {
                older.append(item)
            }
        }

        var groups: [(String, [HistoryItem])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !past7Days.isEmpty { groups.append(("Previous 7 Days", past7Days)) }
        if !past30Days.isEmpty { groups.append(("Previous 30 Days", past30Days)) }
        if !older.isEmpty { groups.append(("Older", older)) }
        return groups
    }

    func recordSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.lowercased().hasPrefix("http://") ||
           trimmed.lowercased().hasPrefix("https://") ||
           trimmed.lowercased().hasPrefix("localhost:") ||
           trimmed.lowercased().hasPrefix("isa://") ||
           trimmed.lowercased() == "isa:settings" ||
           trimmed.lowercased() == "localhost" {
            return
        }

        let domainPattern = "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(/.*)?$"
        if trimmed.range(of: domainPattern, options: .regularExpression) != nil {
            return
        }

        searchQueries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searchQueries.insert(trimmed, at: 0)
        if searchQueries.count > 100 {
            searchQueries = Array(searchQueries.prefix(100))
        }
        UserDefaults.standard.set(searchQueries, forKey: searchHistoryKey)
    }

    func localSuggestions(for query: String) -> [SuggestionItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()

        var results: [SuggestionItem] = []

        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let searchURL = "https://www.google.com/search?q=\(encoded)"
            results.append(SuggestionItem(query: trimmed, fullURL: searchURL, isRecentSearch: false))
        }

        // Add matching visited pages from browsing history
        var seen = Set<String>()
        seen.insert(trimmed.lowercased())

        for item in historyItems {
            if item.title.lowercased().contains(lower) || item.url.lowercased().contains(lower) {
                let key = item.url.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    results.append(SuggestionItem(query: item.displayTitle, fullURL: item.url, isRecentSearch: true, isHistoryVisit: true))
                }
            }
            if results.count >= 4 { break }
        }

        for pastQuery in searchQueries {
            let pastLower = pastQuery.lowercased()
            if pastLower.contains(lower) && !seen.contains(pastLower) {
                seen.insert(pastLower)
                if let encoded = pastQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    let searchURL = "https://www.google.com/search?q=\(encoded)"
                    results.append(SuggestionItem(query: pastQuery, fullURL: searchURL, isRecentSearch: true))
                }
            }
            if results.count >= 6 { break }
        }

        return results
    }

    func fetchSuggestions(for query: String, completion: @escaping ([SuggestionItem]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }

        let localItems = localSuggestions(for: trimmed)

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=chrome&q=\(encoded)") else {
            completion(localItems)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self,
                  let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count > 1,
                  let remoteSuggestions = json[1] as? [String] else {
                DispatchQueue.main.async {
                    completion(localItems)
                }
                return
            }

            var items: [SuggestionItem] = []
            var seen = Set<String>()

            let directSearchURL = "https://www.google.com/search?q=" + encoded
            items.append(SuggestionItem(query: trimmed, fullURL: directSearchURL, isRecentSearch: false))
            seen.insert(trimmed.lowercased())

            let lower = trimmed.lowercased()

            // Include history matches
            for historyItem in self.historyItems {
                let hLowerTitle = historyItem.title.lowercased()
                let hLowerURL = historyItem.url.lowercased()
                if hLowerTitle.contains(lower) || hLowerURL.contains(lower) {
                    if !seen.contains(hLowerURL) {
                        seen.insert(hLowerURL)
                        items.append(SuggestionItem(query: historyItem.displayTitle, fullURL: historyItem.url, isRecentSearch: true, isHistoryVisit: true))
                    }
                }
                if items.count >= 3 { break }
            }

            for pastQuery in self.searchQueries {
                let pastLower = pastQuery.lowercased()
                if pastLower.contains(lower) && !seen.contains(pastLower) {
                    seen.insert(pastLower)
                    if let sEncoded = pastQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        let sURL = "https://www.google.com/search?q=" + sEncoded
                        items.append(SuggestionItem(query: pastQuery, fullURL: sURL, isRecentSearch: true))
                    }
                }
                if items.count >= 5 { break }
            }

            for suggestion in remoteSuggestions {
                let sLower = suggestion.lowercased()
                if !seen.contains(sLower) {
                    seen.insert(sLower)
                    if let sEncoded = suggestion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        let sURL = "https://www.google.com/search?q=" + sEncoded
                        items.append(SuggestionItem(query: suggestion, fullURL: sURL, isRecentSearch: false))
                    }
                }
                if items.count >= 7 { break }
            }

            DispatchQueue.main.async {
                completion(items)
            }
        }.resume()
    }
}
