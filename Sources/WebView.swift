import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    @ObservedObject var tab: Tab

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeNSView(context: Context) -> TabContainerView {
        let container = TabContainerView()
        container.update(tab: tab, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: TabContainerView, context: Context) {
        context.coordinator.tab = tab
        nsView.update(tab: tab, coordinator: context.coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var tab: Tab?
        private var navigationStartTime: CFAbsoluteTime = 0

        init(tab: Tab) {
            self.tab = tab
        }

        deinit {
            print("[isa] [DEINIT] WebView.Coordinator deallocated")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                print("[isa] [Download] navigationAction.shouldPerformDownload == true for \(navigationAction.request.url?.absoluteString ?? "")")
                decisionHandler(.download)
                return
            }
            if let url = navigationAction.request.url {
                let ext = url.pathExtension.lowercased()
                let downloadExtensions: Set<String> = ["zip", "dmg", "pkg", "iso", "tar", "gz", "tgz", "7z", "rar", "exe", "bin", "dat"]
                if downloadExtensions.contains(ext) {
                    print("[isa] [Download] Navigation triggered download by file extension: .\(ext) (\(url.absoluteString))")
                    decisionHandler(.download)
                    return
                }
            }
            if navigationAction.targetFrame == nil {
                if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                    DispatchQueue.main.async {
                        self.tab?.onOpenNewTab?(url)
                    }
                }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated && (navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2) {
                if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                    DispatchQueue.main.async {
                        self.tab?.onOpenNewTab?(url)
                    }
                    decisionHandler(.cancel)
                    return
                }
            }
            if navigationAction.targetFrame?.isMainFrame == true, let host = navigationAction.request.url?.host {
                AdBlockController.shared.updateUserScripts(for: webView, host: host)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                if let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
                   disposition.lowercased().contains("attachment") {
                    print("[isa] [Download] Content-Disposition: attachment detected for \(httpResponse.url?.absoluteString ?? "")")
                    decisionHandler(.download)
                    return
                }
            }
            if !navigationResponse.canShowMIMEType {
                print("[isa] [Download] WKWebView cannot show MIME type '\(navigationResponse.response.mimeType ?? "unknown")'. Triggering download...")
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            print("[isa] [Download] WKNavigationAction didBecome WKDownload: \(download.originalRequest?.url?.absoluteString ?? "")")
            DownloadManager.shared.register(download: download)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            let suggestedFilename = navigationResponse.response.suggestedFilename
            print("[isa] [Download] WKNavigationResponse didBecome WKDownload: suggestedFilename='\(suggestedFilename ?? "none")'")
            DownloadManager.shared.register(download: download, suggestedFilename: suggestedFilename)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                DispatchQueue.main.async {
                    self.tab?.onOpenNewTab?(url)
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let host = webView.url?.host {
                AdBlockController.shared.updateUserScripts(for: webView, host: host)
            }
            navigationStartTime = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                self.tab?.pageError = nil
                self.tab?.isLoading = true
            }
            PerformanceMonitor.shared.log(event: "LoadStart", details: webView.url?.absoluteString ?? "")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab?.pageError = nil
                self.tab?.snapshotImage = nil
                self.tab?.lastActiveTime = Date()
                if let url = webView.url, url.absoluteString != "about:blank" {
                    self.tab?.currentURL = url
                }
                let rawTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !rawTitle.isEmpty {
                    self.tab?.pageTitle = rawTitle
                }
                self.tab?.canGoBack = webView.canGoBack
                self.tab?.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - self.navigationStartTime) * 1000)
            DispatchQueue.main.async {
                guard let tab = self.tab else { return }
                tab.snapshotImage = nil
                tab.lastActiveTime = Date()
                tab.isLoading = false
                if let url = webView.url, url.absoluteString != "about:blank" {
                    tab.currentURL = url
                }
                let rawTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !rawTitle.isEmpty {
                    tab.pageTitle = rawTitle
                } else if tab.pageTitle.isEmpty {
                    tab.pageTitle = webView.url?.host ?? "Untitled"
                }
                tab.canGoBack = webView.canGoBack
                tab.canGoForward = webView.canGoForward
                PerformanceMonitor.shared.log(event: "LoadFinish", details: "Loaded \"\(tab.pageTitle)\" in \(durationMs)ms")
                if let host = webView.url?.host {
                    AdBlockController.recordNavigation(for: host)
                }

                if tab.isReloading {
                    let scrollY = tab.savedScrollY
                    if scrollY > 0 {
                        webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))") { _, _ in
                            DispatchQueue.main.async {
                                self.tab?.isReloading = false
                                self.tab?.savedScrollY = 0
                            }
                        }
                    } else {
                        tab.isReloading = false
                        tab.savedScrollY = 0
                    }
                }
            }
            fetchFavicon(for: webView)
        }

        private func fetchFavicon(for webView: WKWebView) {
            let js = "(function(){ let l = document.querySelector(\"link[rel*='icon']\"); return (l && l.href) ? l.href : ''; })()"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self = self else { return }
                var targetURL: URL? = nil
                if let href = result as? String, !href.isEmpty, let u = URL(string: href) {
                    targetURL = u
                } else if let host = webView.url?.host {
                    targetURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
                }
                guard let iconURL = targetURL else { return }
                URLSession.shared.dataTask(with: iconURL) { [weak self] data, _, _ in
                    guard let self = self, let data = data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self.tab?.favicon = image
                    }
                }.resume()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab?.isLoading = false
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                let host = webView.url?.host ?? self.tab?.currentURL?.host ?? ""
                self.tab?.pageError = PageErrorInfo.from(error: error, url: webView.url ?? self.tab?.currentURL, host: host)
            }
            PerformanceMonitor.shared.log(event: "LoadError", details: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab?.isLoading = false
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                let host = webView.url?.host ?? self.tab?.currentURL?.host ?? ""
                self.tab?.pageError = PageErrorInfo.from(error: error, url: webView.url ?? self.tab?.currentURL, host: host)
            }
            PerformanceMonitor.shared.log(event: "LoadError", details: error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DispatchQueue.main.async {
                self.tab?.isLoading = false
                let host = webView.url?.host ?? self.tab?.currentURL?.host ?? ""
                self.tab?.pageError = PageErrorInfo(
                    type: .processCrashed,
                    failingURL: webView.url ?? self.tab?.currentURL,
                    host: host,
                    localizedDescription: "The webpage crashed or was terminated."
                )
            }
            PerformanceMonitor.shared.log(event: "ProcessTerminate", details: "WebContent process crashed for \(webView.url?.absoluteString ?? "unknown")")
        }
    }
}

final class TabContainerView: NSView {
    private weak var currentWebView: WKWebView?
    private var imageView: NSImageView?
    private var reloadingLabel: NSTextField?

    func update(tab: Tab, coordinator: WebView.Coordinator) {
        if let webView = tab.webView {
            if currentWebView !== webView {
                subviews.forEach { $0.removeFromSuperview() }
                currentWebView = webView
                imageView = nil
                reloadingLabel = nil
                webView.navigationDelegate = coordinator
                webView.uiDelegate = coordinator
                webView.autoresizingMask = [.width, .height]
                webView.frame = bounds
                addSubview(webView)
            }
            if tab.isReloading && tab.snapshotImage != nil {
                showReloadingOverlay()
            } else {
                removeReloadingOverlay()
            }
        } else if let snapshot = tab.snapshotImage {
            if currentWebView != nil || imageView?.image !== snapshot {
                subviews.forEach { $0.removeFromSuperview() }
                currentWebView = nil
                reloadingLabel = nil
                let iv = NSImageView(frame: bounds)
                iv.image = snapshot
                iv.imageScaling = .scaleAxesIndependently
                iv.autoresizingMask = [.width, .height]
                addSubview(iv)
                self.imageView = iv
            }
        } else {
            if !subviews.isEmpty {
                subviews.forEach { $0.removeFromSuperview() }
                currentWebView = nil
                imageView = nil
                reloadingLabel = nil
            }
        }
    }

    private func showReloadingOverlay() {
        guard reloadingLabel == nil else { return }
        let label = NSTextField(labelWithString: "Reloading\u{2026}")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.backgroundColor = .windowBackgroundColor.withAlphaComponent(0.85)
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 12, y: bounds.height - label.frame.height - 12)
        label.autoresizingMask = [.maxXMargin, .minYMargin]
        addSubview(label)
        reloadingLabel = label
    }

    private func removeReloadingOverlay() {
        reloadingLabel?.removeFromSuperview()
        reloadingLabel = nil
    }
}

