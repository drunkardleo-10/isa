import Foundation

struct SuggestionItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let displayURL: String
    let displayTitle: String
    let fullURL: String
    let isSearch: Bool
}

final class HistoryManager {
    static let shared = HistoryManager()

    private let storageKey = "browserHistory"
    private var entries: [[String: String]] = []

    init() {
        if let saved = UserDefaults.standard.array(forKey: storageKey) as? [[String: String]] {
            self.entries = saved
        }
    }

    func addEntry(url: String, title: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedURL.hasPrefix("about:") else { return }
        entries.removeAll { $0["url"] == trimmedURL }
        entries.insert(["url": trimmedURL, "title": title], at: 0)
        if entries.count > 200 {
            entries = Array(entries.prefix(200))
        }
        UserDefaults.standard.set(entries, forKey: storageKey)
    }

    func localSuggestions(for query: String) -> [SuggestionItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()

        var results: [SuggestionItem] = []
        var seenURLs = Set<String>()

        for entry in entries {
            guard let url = entry["url"], let title = entry["title"] else { continue }
            let lowerURL = url.lowercased()
            let lowerTitle = title.lowercased()
            if lowerURL.contains(lower) || lowerTitle.contains(lower) {
                if !seenURLs.contains(url) {
                    seenURLs.insert(url)
                    let cleanDisplay = url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: "")
                    results.append(SuggestionItem(displayURL: cleanDisplay, displayTitle: title, fullURL: url, isSearch: false))
                }
            }
            if results.count >= 3 { break }
        }

        let searchURL = "https://www.google.com/search?q=" + (trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)
        results.append(SuggestionItem(displayURL: "\(trimmed) - Google Search", displayTitle: "", fullURL: searchURL, isSearch: true))

        return results
    }

    func fetchSuggestions(for query: String, completion: @escaping ([SuggestionItem]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }

        let localMatches = localSuggestions(for: trimmed)

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=chrome&q=\(encoded)") else {
            completion(localMatches)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count > 1,
                  let suggestions = json[1] as? [String] else {
                DispatchQueue.main.async {
                    completion(localMatches)
                }
                return
            }

            var items: [SuggestionItem] = []

            for local in localMatches where !local.isSearch {
                items.append(local)
            }

            let directSearchURL = "https://www.google.com/search?q=" + encoded
            items.append(SuggestionItem(displayURL: "\(trimmed) - Google Search", displayTitle: "", fullURL: directSearchURL, isSearch: true))

            let topSuggestions = suggestions.filter { $0.lowercased() != trimmed.lowercased() }.prefix(4)
            for suggestion in topSuggestions {
                if let sEncoded = suggestion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    let sURL = "https://www.google.com/search?q=" + sEncoded
                    items.append(SuggestionItem(displayURL: suggestion, displayTitle: "", fullURL: sURL, isSearch: true))
                }
            }

            DispatchQueue.main.async {
                completion(items)
            }
        }.resume()
    }
}
