import Foundation
import WebKit
import Combine
import SwiftUI

final class TabFindState: ObservableObject {
    weak var tab: Tab?

    @Published var isPresented: Bool = false
    @Published var query: String = "" {
        didSet {
            if query != oldValue {
                executeSearch()
            }
        }
    }
    @Published var currentIndex: Int = 0
    @Published var totalMatches: Int = 0

    init(tab: Tab? = nil) {
        self.tab = tab
    }

    private static let injectionScript: String = """
    window.__isaFind = window.__isaFind || {
        ranges: [],
        currentIndex: -1,
        init() {
            if (!document.getElementById("__isa_find_style")) {
                const style = document.createElement("style");
                style.id = "__isa_find_style";
                style.textContent = `
                    ::highlight(isa-find) {
                        background-color: rgba(255, 224, 102, 0.7);
                        color: currentColor;
                    }
                    ::highlight(isa-find-active) {
                        background-color: rgba(255, 146, 43, 0.95);
                        color: #ffffff;
                    }
                `;
                (document.head || document.documentElement).appendChild(style);
            }
        },
        search(term) {
            this.init();
            this.clear();
            if (!term || typeof term !== "string" || term.length === 0) {
                return { total: 0, current: 0 };
            }
            const textNodes = [];
            const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                    const parent = node.parentElement;
                    if (!parent) return NodeFilter.FILTER_REJECT;
                    const tag = parent.tagName.toUpperCase();
                    if (tag === "SCRIPT" || tag === "STYLE" || tag === "NOSCRIPT" || tag === "TEXTAREA") {
                        return NodeFilter.FILTER_REJECT;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            while (walker.nextNode()) {
                textNodes.push(walker.currentNode);
            }

            const lowerTerm = term.toLowerCase();
            const termLen = term.length;
            this.ranges = [];

            for (const node of textNodes) {
                const text = (node.nodeValue || "").toLowerCase();
                let start = 0;
                while ((start = text.indexOf(lowerTerm, start)) !== -1) {
                    const range = new Range();
                    range.setStart(node, start);
                    range.setEnd(node, start + termLen);
                    this.ranges.push(range);
                    start += termLen;
                }
            }

            if (this.ranges.length > 0 && typeof CSS !== "undefined" && CSS.highlights) {
                CSS.highlights.set("isa-find", new Highlight(...this.ranges));
                this.currentIndex = 0;
                this.updateActive();
                return { total: this.ranges.length, current: 1 };
            }
            return { total: 0, current: 0 };
        },
        next() {
            if (!this.ranges || this.ranges.length === 0) return { total: 0, current: 0 };
            this.currentIndex = (this.currentIndex + 1) % this.ranges.length;
            this.updateActive();
            return { total: this.ranges.length, current: this.currentIndex + 1 };
        },
        prev() {
            if (!this.ranges || this.ranges.length === 0) return { total: 0, current: 0 };
            this.currentIndex = (this.currentIndex - 1 + this.ranges.length) % this.ranges.length;
            this.updateActive();
            return { total: this.ranges.length, current: this.currentIndex + 1 };
        },
        updateActive() {
            const activeRange = this.ranges[this.currentIndex];
            if (activeRange && typeof CSS !== "undefined" && CSS.highlights) {
                CSS.highlights.set("isa-find-active", new Highlight(activeRange));
                const el = activeRange.startContainer.parentElement;
                if (el && typeof el.scrollIntoView === "function") {
                    el.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
                }
            }
        },
        clear() {
            this.ranges = [];
            this.currentIndex = -1;
            if (typeof CSS !== "undefined" && CSS.highlights) {
                CSS.highlights.delete("isa-find");
                CSS.highlights.delete("isa-find-active");
            }
        }
    };
    """

    func show() {
        withAnimation(.easeOut(duration: 0.18)) {
            tab?.isFindPresented = true
            isPresented = true
        }
        tab?.objectWillChange.send()
        if !query.isEmpty {
            executeSearch()
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) {
            tab?.isFindPresented = false
            isPresented = false
        }
        tab?.objectWillChange.send()
        clearHighlights()
    }

    func findNext() {
        guard isPresented, let webView = tab?.webView else { return }
        let js = "window.__isaFind ? window.__isaFind.next() : { total: 0, current: 0 };"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            self?.handleResult(result)
        }
    }

    func findPrevious() {
        guard isPresented, let webView = tab?.webView else { return }
        let js = "window.__isaFind ? window.__isaFind.prev() : { total: 0, current: 0 };"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            self?.handleResult(result)
        }
    }

    private func executeSearch() {
        guard let webView = tab?.webView else {
            currentIndex = 0
            totalMatches = 0
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearHighlights()
            return
        }

        guard let encodedData = try? JSONSerialization.data(withJSONObject: [trimmed]),
              let jsonArray = String(data: encodedData, encoding: .utf8) else {
            return
        }

        let js = """
        (() => {
            \(Self.injectionScript)
            return window.__isaFind.search(\(jsonArray)[0]);
        })()
        """

        webView.evaluateJavaScript(js) { [weak self] result, _ in
            self?.handleResult(result)
        }
    }

    private func clearHighlights() {
        currentIndex = 0
        totalMatches = 0
        guard let webView = tab?.webView else { return }
        let js = "if (window.__isaFind) { window.__isaFind.clear(); }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func handleResult(_ result: Any?) {
        guard let dict = result as? [String: Any] else { return }
        DispatchQueue.main.async {
            self.totalMatches = dict["total"] as? Int ?? 0
            self.currentIndex = dict["current"] as? Int ?? 0
        }
    }
}
