import Foundation
import WebKit
import Combine
import SwiftUI
import AppKit
import UserNotifications

enum DownloadStatus: Equatable {
    case downloading
    case completed
    case failed(String)
    case cancelled
}

final class DownloadItem: Identifiable, ObservableObject {
    let id: UUID = UUID()
    @Published var suggestedFilename: String
    @Published var destinationURL: URL?
    @Published var progress: Double = 0.0
    @Published var bytesDownloaded: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var status: DownloadStatus = .downloading
    let startDate: Date = Date()
    weak var download: WKDownload?
    private var progressObservation: NSKeyValueObservation?

    var displayName: String {
        if let dest = destinationURL?.lastPathComponent, !dest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dest
        }
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "/" {
            return trimmed
        }
        return "download"
    }

    init(suggestedFilename: String, download: WKDownload) {
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "/" {
            self.suggestedFilename = trimmed
        } else if let last = download.originalRequest?.url?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty, last != "/" {
            self.suggestedFilename = last
        } else {
            self.suggestedFilename = "download"
        }
        self.download = download
        setupProgressObservation(download.progress)
    }

    private func setupProgressObservation(_ prog: Progress) {
        progressObservation = prog.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                guard let self = self, self.status == .downloading else { return }
                self.progress = p.fractionCompleted
                self.bytesDownloaded = p.completedUnitCount
                self.totalBytes = p.totalUnitCount
            }
        }
    }

    func cancel() {
        guard status == .downloading else { return }
        status = .cancelled
        progressObservation?.invalidate()
        progressObservation = nil
        download?.cancel { _ in }
        if let url = destinationURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    deinit {
        progressObservation?.invalidate()
    }
}

final class DownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    @Published var items: [DownloadItem] = []
    @Published var hasUnreadCompletion: Bool = false
    private var itemSubscriptions: [UUID: AnyCancellable] = [:]

    var activeDownloads: [DownloadItem] {
        items.filter { $0.status == .downloading }
    }

    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var shouldShowTopBarButton: Bool {
        hasActiveDownloads || hasUnreadCompletion || !items.isEmpty
    }

    override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func removeItem(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let item = items[idx]
            if item.status == .downloading {
                item.cancel()
            }
            itemSubscriptions.removeValue(forKey: id)
            items.remove(at: idx)
            objectWillChange.send()
        }
    }

    func clearFinished() {
        for item in items where item.status != .downloading {
            itemSubscriptions.removeValue(forKey: item.id)
        }
        items.removeAll(where: { $0.status != .downloading })
        objectWillChange.send()
    }

    func register(download: WKDownload, suggestedFilename: String? = nil) {
        var name: String? = suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        if name?.isEmpty == true || name == "/" {
            name = nil
        }
        if name == nil, let last = download.originalRequest?.url?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty, last != "/" {
            name = last
        }
        let finalName = name ?? "download"
        print("[isa] [Download] Registering download: '\(finalName)' (suggested: '\(suggestedFilename ?? "none")')")
        let item = DownloadItem(suggestedFilename: finalName, download: download)
        download.delegate = self

        itemSubscriptions[item.id] = item.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            items.insert(item, at: 0)
            if items.count > 50 {
                let removed = items.suffix(from: 50)
                for r in removed {
                    itemSubscriptions.removeValue(forKey: r.id)
                }
                items = Array(items.prefix(50))
            }
        }
        objectWillChange.send()
        print("[isa] [Download] Download item added. Total active items: \(items.count)")
        PerformanceMonitor.shared.log(event: "DownloadStart", details: finalName)
    }

    var customDownloadsFolder: (() -> URL?)?

    static func uniqueDestinationURL(for suggestedFilename: String, in customFolder: URL? = nil) -> URL {
        let downloadsDir = customFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = (trimmed.isEmpty || trimmed == "/") ? "download" : trimmed
        let fileExtension = (cleaned as NSString).pathExtension
        let baseName = (cleaned as NSString).deletingPathExtension

        var destination = downloadsDir.appendingPathComponent(cleaned)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let nextName = fileExtension.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(fileExtension)"
            destination = downloadsDir.appendingPathComponent(nextName)
            counter += 1
        }
        return destination
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        var actualName = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if actualName.isEmpty || actualName == "download" || actualName == "/" {
            if let respName = response.suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines), !respName.isEmpty && respName != "/" {
                actualName = respName
            } else if let urlName = response.url?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines), !urlName.isEmpty && urlName != "/" {
                actualName = urlName
            } else {
                actualName = "download"
            }
        }
        let destinationURL = Self.uniqueDestinationURL(for: actualName, in: customDownloadsFolder?())
        print("[isa] [Download] Destination resolved for '\(actualName)' -> '\(destinationURL.path)'")
        DispatchQueue.main.async {
            if let item = self.items.first(where: { $0.download === download }) {
                item.destinationURL = destinationURL
                item.suggestedFilename = destinationURL.lastPathComponent
            }
            self.objectWillChange.send()
        }
        completionHandler(destinationURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        print("[isa] [Download] WKDownload finished!")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let item = self.items.first(where: { $0.download === download }) {
                print("[isa] [Download] Completed item: '\(item.displayName)' at '\(item.destinationURL?.path ?? "")'")
                item.progress = 1.0
                item.status = .completed
                self.hasUnreadCompletion = true
                self.sendCompletionNotification(for: item)
                self.objectWillChange.send()
                PerformanceMonitor.shared.log(event: "DownloadFinish", details: item.displayName)
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        print("[isa] [Download] WKDownload failed with error: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let item = self.items.first(where: { $0.download === download }) {
                print("[isa] [Download] Marked item as failed: '\(item.displayName)'")
                if item.status != .cancelled {
                    item.status = .failed(error.localizedDescription)
                }
                if let url = item.destinationURL, FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                self.objectWillChange.send()
                PerformanceMonitor.shared.log(event: "DownloadError", details: "\(item.displayName): \(error.localizedDescription)")
            }
        }
    }

    private func sendCompletionNotification(for item: DownloadItem) {
        NSSound(named: "Glass")?.play()
        NSApp?.requestUserAttention(.informationalRequest)

        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = item.displayName
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
