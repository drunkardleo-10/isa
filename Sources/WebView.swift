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
        var tab: Tab
        private var navigationStartTime: CFAbsoluteTime = 0

        init(tab: Tab) {
            self.tab = tab
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil {
                if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                    DispatchQueue.main.async {
                        self.tab.onOpenNewTab?(url)
                    }
                }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated && (navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2) {
                if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                    DispatchQueue.main.async {
                        self.tab.onOpenNewTab?(url)
                    }
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                DispatchQueue.main.async {
                    self.tab.onOpenNewTab?(url)
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            navigationStartTime = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                self.tab.isLoading = true
            }
            PerformanceMonitor.shared.log(event: "LoadStart", details: webView.url?.absoluteString ?? "")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.snapshotImage = nil
                self.tab.lastActiveTime = Date()
                if let url = webView.url, url.absoluteString != "about:blank" {
                    self.tab.currentURL = url
                }
                let rawTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !rawTitle.isEmpty {
                    self.tab.pageTitle = rawTitle
                }
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - self.navigationStartTime) * 1000)
            DispatchQueue.main.async {
                self.tab.snapshotImage = nil
                self.tab.lastActiveTime = Date()
                self.tab.isLoading = false
                if let url = webView.url, url.absoluteString != "about:blank" {
                    self.tab.currentURL = url
                }
                let rawTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !rawTitle.isEmpty {
                    self.tab.pageTitle = rawTitle
                } else if self.tab.pageTitle.isEmpty {
                    self.tab.pageTitle = webView.url?.host ?? "Untitled"
                }
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward
                PerformanceMonitor.shared.log(event: "LoadFinish", details: "Loaded \"\(self.tab.pageTitle)\" in \(durationMs)ms")
                if let host = webView.url?.host {
                    AdBlockController.recordNavigation(for: host)
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
                        self.tab.favicon = image
                    }
                }.resume()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
            PerformanceMonitor.shared.log(event: "LoadError", details: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
            PerformanceMonitor.shared.log(event: "LoadError", details: error.localizedDescription)
        }
    }
}

final class TabContainerView: NSView {
    private weak var currentWebView: WKWebView?
    private var imageView: NSImageView?

    func update(tab: Tab, coordinator: WebView.Coordinator) {
        if let webView = tab.webView {
            if currentWebView !== webView {
                subviews.forEach { $0.removeFromSuperview() }
                currentWebView = webView
                imageView = nil
                webView.navigationDelegate = coordinator
                webView.uiDelegate = coordinator
                webView.autoresizingMask = [.width, .height]
                webView.frame = bounds
                addSubview(webView)
            }
        } else if let snapshot = tab.snapshotImage {
            if currentWebView != nil || imageView?.image !== snapshot {
                subviews.forEach { $0.removeFromSuperview() }
                currentWebView = nil
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
            }
        }
    }
}

