import Foundation
import AppKit
import SQLite3
import UniformTypeIdentifiers

enum WebKitSourceType: String, CaseIterable, Identifiable {
    case safari = "safari"
    case safariTP = "safari_tp"
    case orion = "orion"
    case file = "file"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .safariTP: return "Safari Tech Preview"
        case .orion: return "Orion"
        case .file: return "Custom Bookmarks File"
        }
    }

    var iconName: String {
        switch self {
        case .safari: return "safari"
        case .safariTP: return "safari.fill"
        case .orion: return "network"
        case .file: return "doc.text"
        }
    }

    var subtitle: String {
        switch self {
        case .safari: return "Default macOS WebKit browser"
        case .safariTP: return "Developer WebKit build"
        case .orion: return "Native WebKit privacy browser"
        case .file: return "Exported HTML or Bookmarks.plist"
        }
    }

    var isDetected: Bool {
        let fm = FileManager.default
        switch self {
        case .safari:
            return true
        case .safariTP:
            return fm.fileExists(atPath: "/Applications/Safari Technology Preview.app") ||
                   fm.fileExists(atPath: fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/SafariTechnologyPreview").path)
        case .orion:
            return fm.fileExists(atPath: "/Applications/Orion.app") ||
                   fm.fileExists(atPath: fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Orion.app").path) ||
                   fm.fileExists(atPath: fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Orion").path)
        case .file:
            return true
        }
    }

    var defaultBookmarksURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .safari:
            return home.appendingPathComponent("Library/Safari/Bookmarks.plist")
        case .safariTP:
            return home.appendingPathComponent("Library/SafariTechnologyPreview/Bookmarks.plist")
        case .orion:
            let fav = home.appendingPathComponent("Library/Application Support/Orion/Defaults/favourites.plist")
            if FileManager.default.fileExists(atPath: fav.path) { return fav }
            return home.appendingPathComponent("Library/Application Support/Orion/Defaults/bookmarks.plist")
        case .file:
            return nil
        }
    }

    var defaultHistoryURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .safari:
            return home.appendingPathComponent("Library/Safari/History.db")
        case .safariTP:
            return home.appendingPathComponent("Library/SafariTechnologyPreview/History.db")
        case .orion:
            return home.appendingPathComponent("Library/Application Support/Orion/Defaults/history.db")
        case .file:
            return nil
        }
    }
}

struct WebKitImportResult {
    var bookmarksCount: Int = 0
    var historyCount: Int = 0
    var message: String = ""
    var requiresPermissionPrompt: Bool = false
}

final class WebKitImporter {
    static let shared = WebKitImporter()

    func pickBookmarksFile(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose Safari Bookmarks.plist or an exported HTML Bookmarks file"
        panel.prompt = "Choose File"
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.propertyList, .html, .plainText, .data]
        } else {
            panel.allowedFileTypes = ["plist", "html", "htm"]
        }
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url)
            } else {
                completion(nil)
            }
        }
    }

    func parseBookmarks(at url: URL) -> [BookmarkItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let string = String(data: data, encoding: .utf8), (string.contains("<DL>") || string.contains("<A HREF=") || string.contains("<a href=")) {
            return parseHTMLBookmarks(content: string)
        }
        return parseSafariPlist(data: data)
    }

    func parseSafariPlist(data: Data) -> [BookmarkItem] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return []
        }
        var results: [BookmarkItem] = []

        func traverse(node: [String: Any], currentFolder: String?) {
            let type = node["WebBookmarkType"] as? String ?? ""
            if type == "WebBookmarkTypeList" {
                let title = (node["Title"] as? String) ?? currentFolder
                if let children = node["Children"] as? [[String: Any]] {
                    for child in children {
                        traverse(node: child, currentFolder: title)
                    }
                }
            } else if type == "WebBookmarkTypeLeaf" {
                if let urlString = node["URLString"] as? String, !urlString.isEmpty {
                    let uriDict = node["URIDictionary"] as? [String: Any]
                    let title = (uriDict?["title"] as? String) ?? (node["Title"] as? String) ?? urlString
                    results.append(BookmarkItem(title: title, url: urlString, folder: currentFolder))
                }
            }
        }

        traverse(node: plist, currentFolder: nil)
        return results
    }

    func parseHTMLBookmarks(content: String) -> [BookmarkItem] {
        var items: [BookmarkItem] = []
        let pattern = "<a\\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)<\\/a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let urlRange = Range(match.range(at: 1), in: content),
                  let titleRange = Range(match.range(at: 2), in: content) else { continue }
            let urlStr = String(content[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let titleStr = String(content[titleRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") {
                items.append(BookmarkItem(title: titleStr.isEmpty ? urlStr : titleStr, url: urlStr))
            }
        }
        return items
    }

    func parseHistory(at url: URL, limit: Int = 1500) -> [HistoryItem] {
        var results: [HistoryItem] = []
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = db else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT history_items.url, history_visits.title, history_visits.visit_time
        FROM history_items
        JOIN history_visits ON history_items.id = history_visits.history_item
        ORDER BY history_visits.visit_time DESC LIMIT \(limit)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement = statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawURL = sqlite3_column_text(statement, 0) else { continue }
            let urlStr = String(cString: rawURL)
            let titleStr: String
            if let rawTitle = sqlite3_column_text(statement, 1) {
                titleStr = String(cString: rawTitle)
            } else {
                titleStr = URL(string: urlStr)?.host ?? urlStr
            }
            let visitTime = sqlite3_column_double(statement, 2)
            let date = Date(timeIntervalSinceReferenceDate: visitTime)
            results.append(HistoryItem(url: urlStr, title: titleStr, visitTime: date))
        }

        return results
    }

    func performImport(
        source: WebKitSourceType,
        selectedFileURL: URL?,
        importBookmarks: Bool,
        importHistory: Bool,
        completion: @escaping (WebKitImportResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var result = WebKitImportResult()
            var importedBookmarks = 0
            var importedHistory = 0
            var hitPermissionIssue = false

            if importBookmarks {
                let targetURL = (source == .file) ? selectedFileURL : source.defaultBookmarksURL
                if let targetURL = targetURL {
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        let parsed = self.parseBookmarks(at: targetURL)
                        if !parsed.isEmpty {
                            importedBookmarks = BookmarkManager.shared.importItems(parsed)
                        } else if source == .safari || source == .safariTP {
                            if (try? Data(contentsOf: targetURL)) == nil {
                                hitPermissionIssue = true
                            }
                        }
                    } else if source == .safari || source == .safariTP {
                        hitPermissionIssue = true
                    }
                }
            }

            if importHistory {
                let historyURL = source.defaultHistoryURL
                if let historyURL = historyURL {
                    if FileManager.default.fileExists(atPath: historyURL.path) {
                        let parsed = self.parseHistory(at: historyURL)
                        if !parsed.isEmpty {
                            importedHistory = HistoryManager.shared.importItems(parsed)
                        } else if source == .safari || source == .safariTP {
                            hitPermissionIssue = true
                        }
                    }
                }
            }

            result.bookmarksCount = importedBookmarks
            result.historyCount = importedHistory
            result.requiresPermissionPrompt = hitPermissionIssue && importedBookmarks == 0 && importedHistory == 0

            var parts: [String] = []
            if importedBookmarks > 0 {
                parts.append("\(importedBookmarks) bookmarks")
            }
            if importedHistory > 0 {
                parts.append("\(importedHistory) history items")
            }

            if !parts.isEmpty {
                result.message = "Successfully imported " + parts.joined(separator: " and ")
            } else if result.requiresPermissionPrompt {
                result.message = "Safari files are protected by macOS. Choose your Bookmarks.plist or an exported bookmarks HTML file below."
            } else {
                result.message = "No items found to import from \(source.displayName)."
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
