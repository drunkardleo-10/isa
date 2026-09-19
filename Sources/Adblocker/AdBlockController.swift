import Foundation
import WebKit

public final class AdBlockController {
    public static let shared = AdBlockController()

    public static let ruleListIdentifier = "isa.adblock.rules"

    private enum State {
        case uninitialized
        case loading
        case ready(WKContentRuleList)
        case failed
    }

    private let lock = NSLock()
    private var state: State = .uninitialized
    private var cosmeticUserScript: WKUserScript?
    private var cosmeticRulesByDomain: [String: String] = [:]
    private var totalCosmeticSelectorsCount: Int = 17_166
    private var networkRuleCount: Int = 110_664
    private var domainsWithRulesAppliedSession = Set<String>()

    public var isEnabled: Bool = true

    public init() {
        loadCosmeticFilterScript()
        loadNetworkRuleCountAsync()
        startLoadingRuleListIfNeeded()
    }

    
    public static func apply(to configuration: WKWebViewConfiguration) {
        shared.apply(to: configuration)
    }

    
    
    
    public func apply(to configuration: WKWebViewConfiguration) {
        startLoadingRuleListIfNeeded()

        if ProcessInfo.processInfo.environment["ISA_DISABLE_COSMETIC"] != "1",
           let cosmeticScript = cosmeticUserScript {
            configuration.userContentController.addUserScript(cosmeticScript)
        }

        
        lock.lock()
        if case .ready(let ruleList) = state {
            lock.unlock()
            configuration.userContentController.add(ruleList)
            return
        }
        lock.unlock()

        
        waitForReadiness()

        lock.lock()
        defer { lock.unlock() }
        if case .ready(let ruleList) = state {
            configuration.userContentController.add(ruleList)
        } else {
            PerformanceMonitor.shared.log(event: "AdBlock", details: "Rule list unavailable; proceeding without content blocker")
        }
    }

    private func loadCosmeticFilterScript() {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "cosmetic-filters", withExtension: "json"),
            Bundle.main.url(forResource: "cosmetic-filters", withExtension: "json", subdirectory: "rules"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/cosmetic-filters.json"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/rules/cosmetic-filters.json"),
            URL(fileURLWithPath: "rules/cosmetic-filters.json"),
            Bundle.main.bundleURL.appendingPathComponent("rules/cosmetic-filters.json")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let jsonString = try? String(contentsOf: url, encoding: .utf8),
              !jsonString.isEmpty else {
            PerformanceMonitor.shared.log(event: "AdBlock", details: "Cosmetic filters file not found or empty")
            return
        }

        let jsSource = """
        (function() {
            if (window.__isa_cosmetic_applied__) return;
            window.__isa_cosmetic_applied__ = true;

            var rules = \(jsonString);
            var hostname = (window.location && window.location.hostname) ? window.location.hostname.toLowerCase() : "";
            if (!hostname) return;

            var parts = hostname.split(".");
            var selectors = [];
            for (var i = 0; i < parts.length - 1; i++) {
                var domain = parts.slice(i).join(".");
                var sel = rules[domain];
                if (sel) {
                    selectors.push(sel);
                }
            }

            if (selectors.length === 0) return;

            var style = document.createElement("style");
            style.setAttribute("type", "text/css");
            style.setAttribute("data-isa-adblock", "cosmetic");
            style.textContent = selectors.join(",\\n") + " { display: none !important; }";

            function tryInject() {
                var target = document.head || document.documentElement;
                if (target) {
                    target.appendChild(style);
                    return true;
                }
                return false;
            }

            if (!tryInject()) {
                if (window.MutationObserver) {
                    var observer = new MutationObserver(function() {
                        if (tryInject()) {
                            observer.disconnect();
                        }
                    });
                    observer.observe(document, { childList: true, subtree: true });
                }
                document.addEventListener("DOMContentLoaded", tryInject, { once: true });
            }
        })();
        """

        if let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            self.lock.lock()
            self.cosmeticRulesByDomain = dict
            var count = 0
            for (_, selectors) in dict {
                count += selectors.components(separatedBy: ",\n").count
            }
            self.totalCosmeticSelectorsCount = count
            self.lock.unlock()
        }

        self.cosmeticUserScript = WKUserScript(
            source: jsSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        PerformanceMonitor.shared.log(event: "AdBlock", details: "Cosmetic filtering script loaded and compiled successfully")
    }

    private func startLoadingRuleListIfNeeded() {
        lock.lock()
        guard case .uninitialized = state else {
            lock.unlock()
            return
        }
        state = .loading
        lock.unlock()

        guard let store = WKContentRuleListStore.default() else {
            PerformanceMonitor.shared.log(event: "AdBlockError", details: "WKContentRuleListStore is unavailable")
            transition(to: .failed)
            return
        }

        PerformanceMonitor.shared.log(event: "AdBlockLookup", details: "Checking persistent store for identifier: \(Self.ruleListIdentifier)")

        
        store.lookUpContentRuleList(forIdentifier: Self.ruleListIdentifier) { [weak self] ruleList, error in
            guard let self = self else { return }

            if let ruleList = ruleList {
                PerformanceMonitor.shared.log(event: "AdBlockLookup", details: "Found persisted compiled rule list (\(ruleList.identifier ?? ""))")
                self.transition(to: .ready(ruleList))
                return
            }

            PerformanceMonitor.shared.log(event: "AdBlockCompile", details: "Not in persistent store. Compiling from bundle...")
            self.compileFromBundle(store: store)
        }
    }

    private func compileFromBundle(store: WKContentRuleListStore) {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "content-blocker", withExtension: "json"),
            Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "rules"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/content-blocker.json"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/rules/content-blocker.json"),
            URL(fileURLWithPath: "rules/content-blocker.json"),
            Bundle.main.bundleURL.appendingPathComponent("rules/content-blocker.json")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            PerformanceMonitor.shared.log(event: "AdBlockError", details: "Failed to locate content-blocker.json in app bundle")
            transition(to: .failed)
            return
        }

        guard let jsonString = try? String(contentsOf: url, encoding: .utf8) else {
            PerformanceMonitor.shared.log(event: "AdBlockError", details: "Failed to read content-blocker.json from \(url.path)")
            transition(to: .failed)
            return
        }

        let startTime = Date()
        PerformanceMonitor.shared.log(event: "AdBlockCompile", details: "Compiling rule list from JSON (\(jsonString.utf8.count) bytes)...")

        store.compileContentRuleList(
            forIdentifier: Self.ruleListIdentifier,
            encodedContentRuleList: jsonString
        ) { [weak self] ruleList, error in
            guard let self = self else { return }

            if let error = error {
                PerformanceMonitor.shared.log(event: "AdBlockError", details: "Compilation failed: \(error.localizedDescription)")
                self.transition(to: .failed)
                return
            }

            if let ruleList = ruleList {
                let duration = Date().timeIntervalSince(startTime)
                PerformanceMonitor.shared.log(event: "AdBlockCompile", details: "Successfully compiled and persisted rule list in \(String(format: "%.2f", duration))s")
                self.transition(to: .ready(ruleList))
            } else {
                self.transition(to: .failed)
            }
        }
    }

    private func transition(to newState: State) {
        lock.lock()
        state = newState
        lock.unlock()
    }

    
    
    
    private func waitForReadiness(timeout: TimeInterval = 10.0) {
        let deadline = Date().addingTimeInterval(timeout)

        if Thread.isMainThread {
            while Date() < deadline {
                lock.lock()
                if case .loading = state {
                    lock.unlock()
                    
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                } else {
                    lock.unlock()
                    break
                }
            }
        } else {
            while Date() < deadline {
                lock.lock()
                if case .loading = state {
                    lock.unlock()
                    Thread.sleep(forTimeInterval: 0.02)
                } else {
                    lock.unlock()
                    break
                }
            }
        }
    }

    private func loadNetworkRuleCountAsync() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let candidateURLs: [URL?] = [
                Bundle.main.url(forResource: "content-blocker", withExtension: "json"),
                Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "rules"),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/content-blocker.json"),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/rules/content-blocker.json"),
                URL(fileURLWithPath: "rules/content-blocker.json"),
                Bundle.main.bundleURL.appendingPathComponent("rules/content-blocker.json")
            ]

            guard let url = candidateURLs.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }

            self?.lock.lock()
            self?.networkRuleCount = jsonArray.count
            self?.lock.unlock()
        }
    }

    

    public var totalRuleCounts: (network: Int, cosmetic: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (networkRuleCount, totalCosmeticSelectorsCount)
    }

    public static var totalRuleCounts: (network: Int, cosmetic: Int) {
        shared.totalRuleCounts
    }

    public func cosmeticRuleCount(for hostOrURL: String) -> Int {
        var hostname: String
        if hostOrURL.contains("://"), let url = URL(string: hostOrURL), let host = url.host {
            hostname = host.lowercased()
        } else {
            hostname = hostOrURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if let colonIndex = hostname.firstIndex(of: ":") {
            hostname = String(hostname[..<colonIndex])
        }
        while hostname.hasSuffix(".") {
            hostname.removeLast()
        }
        guard !hostname.isEmpty else { return 0 }

        let parts = hostname.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return 0 }

        lock.lock()
        let rules = cosmeticRulesByDomain
        lock.unlock()

        var total = 0
        for i in 0..<(parts.count - 1) {
            let domain = parts[i...].joined(separator: ".")
            if let sel = rules[domain] {
                total += sel.components(separatedBy: ",\n").count
            }
        }
        return total
    }

    public static func cosmeticRuleCount(for hostOrURL: String) -> Int {
        shared.cosmeticRuleCount(for: hostOrURL)
    }

    public func isProtectionActive(for domain: String? = nil) -> Bool {
        guard isEnabled else { return false }
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .ready, .loading, .uninitialized:
            return true
        case .failed:
            return false
        }
    }

    public static func isProtectionActive(for domain: String? = nil) -> Bool {
        shared.isProtectionActive(for: domain)
    }

    public var sessionSitesWithRulesCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return domainsWithRulesAppliedSession.count
    }

    public static var sessionSitesWithRulesCount: Int {
        shared.sessionSitesWithRulesCount
    }

    public func recordNavigation(for host: String) {
        if cosmeticRuleCount(for: host) > 0 {
            lock.lock()
            domainsWithRulesAppliedSession.insert(host.lowercased())
            lock.unlock()
        }
    }

    public static func recordNavigation(for host: String) {
        shared.recordNavigation(for: host)
    }
}
