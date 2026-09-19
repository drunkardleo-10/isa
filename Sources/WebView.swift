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

        init(tab: Tab) {
            self.tab = tab
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.isLoading = true
            }
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
            DispatchQueue.main.async {
                self.tab.isLoading = false
                self.tab.currentURL = webView.url
                self.tab.pageTitle = webView.title ?? webView.url?.host ?? "Untitled"
                self.tab.canGoBack = webView.canGoBack
                self.tab.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.tab.isLoading = false
            }
        }
    }
}
