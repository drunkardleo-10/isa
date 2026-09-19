import Foundation

struct SuggestionItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let query: String
    let fullURL: String
    let isRecentSearch: Bool

    var displayURL: String { query }
    var displayTitle: String { isRecentSearch ? "Search history" : "" }
    var isSearch: Bool { true }
}

final class HistoryManager {
    static let shared = HistoryManager()

    private let searchHistoryKey = "searchHistory"
    private var searchQueries: [String] = []

    init() {
        
        UserDefaults.standard.removeObject(forKey: "browserHistory")

        if let saved = UserDefaults.standard.stringArray(forKey: searchHistoryKey) {
            self.searchQueries = saved
        }
    }

    func recordSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        
        if trimmed.lowercased().hasPrefix("http://") ||
           trimmed.lowercased().hasPrefix("https://") ||
           trimmed.lowercased().hasPrefix("localhost:") ||
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

        
        for pastQuery in searchQueries {
            if pastQuery.lowercased().contains(lower) && pastQuery.caseInsensitiveCompare(trimmed) != .orderedSame {
                if let encoded = pastQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    let searchURL = "https://www.google.com/search?q=\(encoded)"
                    results.append(SuggestionItem(query: pastQuery, fullURL: searchURL, isRecentSearch: true))
                }
            }
            if results.count >= 4 { break }
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
            for pastQuery in self.searchQueries {
                let pastLower = pastQuery.lowercased()
                if pastLower.contains(lower) && !seen.contains(pastLower) {
                    seen.insert(pastLower)
                    if let sEncoded = pastQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        let sURL = "https://www.google.com/search?q=" + sEncoded
                        items.append(SuggestionItem(query: pastQuery, fullURL: sURL, isRecentSearch: true))
                    }
                }
                if items.count >= 3 { break }
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
                if items.count >= 6 { break }
            }

            DispatchQueue.main.async {
                completion(items)
            }
        }.resume()
    }
}

