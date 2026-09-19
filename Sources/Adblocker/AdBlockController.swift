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

    public init() {
        startLoadingRuleListIfNeeded()
    }

    /// Exposes a single class method to apply the compiled rule list to a WKWebViewConfiguration.
    public static func apply(to configuration: WKWebViewConfiguration) {
        shared.apply(to: configuration)
    }

    /// Applies the compiled rule list to the configuration's userContentController.
    /// Thread-safe and idempotent. If called during cold launch before lookup/compile finishes,
    /// it synchronizes so that the rule list is attached before the WKWebView is instantiated.
    public func apply(to configuration: WKWebViewConfiguration) {
        startLoadingRuleListIfNeeded()

        // Fast path: rule list is already compiled and cached in memory
        lock.lock()
        if case .ready(let ruleList) = state {
            lock.unlock()
            configuration.userContentController.add(ruleList)
            return
        }
        lock.unlock()

        // In-flight synchronization: wait for compilation/lookup to finish so webview is never unshielded
        waitForReadiness()

        lock.lock()
        defer { lock.unlock() }
        if case .ready(let ruleList) = state {
            configuration.userContentController.add(ruleList)
        } else {
            PerformanceMonitor.shared.log(event: "AdBlock", details: "Rule list unavailable; proceeding without content blocker")
        }
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

        // Check persistent store first to avoid recompiling across launches
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

    /// Waits for in-flight compilation/lookup to resolve.
    /// On the main thread, pumps the RunLoop in short slices so WebKit's IPC messages can be delivered
    /// without deadlocking the main queue. Includes a 10s safety timeout to prevent app hangs.
    private func waitForReadiness(timeout: TimeInterval = 10.0) {
        let deadline = Date().addingTimeInterval(timeout)

        if Thread.isMainThread {
            while Date() < deadline {
                lock.lock()
                if case .loading = state {
                    lock.unlock()
                    // Run loop briefly to allow WebKit's completion handler to execute
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
}
