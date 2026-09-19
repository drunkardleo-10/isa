import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    @ObservedObject var tab: Tab

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.tab = tab
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var tab: Tab
        private var navigationStartTime: CFAbsoluteTime = 0

        init(tab: Tab) {
            self.tab = tab
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
                self.tab.currentURL = webView.url
                if let title = webView.title, !title.isEmpty {
                    self.tab.pageTitle = title
                }
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - self.navigationStartTime) * 1000)
            DispatchQueue.main.async {
                self.tab.isLoading = false
                self.tab.currentURL = webView.url
                self.tab.pageTitle = webView.title ?? webView.url?.host ?? "Untitled"
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward
                PerformanceMonitor.shared.log(event: "LoadFinish", details: "Loaded \"\(self.tab.pageTitle)\" in \(durationMs)ms")
                if let url = webView.url?.absoluteString {
                    HistoryManager.shared.addEntry(url: url, title: self.tab.pageTitle)
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
