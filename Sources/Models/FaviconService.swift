import Foundation
import AppKit
import CryptoKit
import SwiftUI

final class FaviconService: ObservableObject {
    static let shared = FaviconService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()
    private let cacheDirectory: URL?

    private init() {
        memoryCache.countLimit = 500
        if let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("com.isa.browser/favicons", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheDirectory = dir
        } else {
            self.cacheDirectory = nil
        }
    }

    func extractHost(from urlOrHost: String) -> String {
        let trimmed = urlOrHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            if let url = URL(string: trimmed), let host = url.host {
                return cleanHost(host)
            }
        }
        if let url = URL(string: "https://\(trimmed)"), let host = url.host {
            return cleanHost(host)
        }
        return cleanHost(trimmed)
    }

    private func cleanHost(_ host: String) -> String {
        var result = host.lowercased()
        if result.hasPrefix("www.") {
            result = String(result.dropFirst(4))
        }
        return result
    }

    private func extractRootHost(from host: String) -> String {
        let parts = host.split(separator: ".")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ".")
        }
        return host
    }

    func cachedFavicon(for urlOrHost: String) -> NSImage? {
        let host = extractHost(from: urlOrHost)
        guard !host.isEmpty else { return nil }

        if let cached = memoryCache.object(forKey: host as NSString) {
            return cached
        }

        if let dir = cacheDirectory {
            let filename = Insecure.MD5.hash(data: Data(host.utf8)).map { String(format: "%02hhx", $0) }.joined()
            let fileURL = dir.appendingPathComponent("\(filename).png")
            if FileManager.default.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let img = NSImage(data: data), img.isValid {
                memoryCache.setObject(img, forKey: host as NSString)
                return img
            }
        }

        return nil
    }

    func setFavicon(_ image: NSImage, for urlOrHost: String) {
        let host = extractHost(from: urlOrHost)
        guard !host.isEmpty, image.isValid else { return }

        memoryCache.setObject(image, forKey: host as NSString)

        if let dir = cacheDirectory {
            DispatchQueue.global(qos: .utility).async {
                let filename = Insecure.MD5.hash(data: Data(host.utf8)).map { String(format: "%02hhx", $0) }.joined()
                let fileURL = dir.appendingPathComponent("\(filename).png")
                if let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: fileURL, options: .atomic)
                }
            }
        }
    }

    func loadFavicon(for urlOrHost: String, completion: @escaping (NSImage?) -> Void) {
        let host = extractHost(from: urlOrHost)
        guard !host.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        if let cached = cachedFavicon(for: host) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        lock.lock()
        if inFlight[host] != nil {
            inFlight[host]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[host] = [completion]
        lock.unlock()

        let rootHost = extractRootHost(from: host)
        var candidates: [URL] = []

        if let googleHost = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
            candidates.append(googleHost)
        }
        if rootHost != host, let googleRoot = URL(string: "https://www.google.com/s2/favicons?domain=\(rootHost)&sz=64") {
            candidates.append(googleRoot)
        }
        if let ddgHost = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            candidates.append(ddgHost)
        }
        if let direct = URL(string: "https://\(host)/favicon.ico") {
            candidates.append(direct)
        }

        fetchNextCandidate(candidates: candidates, host: host)
    }

    private func fetchNextCandidate(candidates: [URL], host: String) {
        guard !candidates.isEmpty else {
            finish(for: host, image: nil)
            return
        }

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
                self.setFavicon(image, for: host)
                self.finish(for: host, image: image)
            } else {
                self.fetchNextCandidate(candidates: remaining, host: host)
            }
        }.resume()
    }

    private func isFallbackGlobe(data: Data) -> Bool {
        if data.count == 726 { return true }
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
        return md5 == "b8a0bf372c762e966cc99ede8682bc71"
    }

    private func finish(for host: String, image: NSImage?) {
        lock.lock()
        let handlers = inFlight.removeValue(forKey: host) ?? []
        lock.unlock()

        DispatchQueue.main.async {
            for handler in handlers {
                handler(image)
            }
        }
    }
}

struct FaviconView: View {
    let url: String
    var fallbackIcon: String = "globe"
    var size: CGFloat = 16
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.2), style: .continuous))
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: max(8, size * 0.72)))
                    .foregroundColor(.accentColor)
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        if let cached = FaviconService.shared.cachedFavicon(for: url) {
            self.image = cached
            return
        }
        FaviconService.shared.loadFavicon(for: url) { loaded in
            self.image = loaded
        }
    }
}
