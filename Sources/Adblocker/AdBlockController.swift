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
    private var scriptletUserScript: WKUserScript?
    private var scriptletsByDomain: [String: [String]] = [:]
    private var totalScriptletSnippetsCount: Int = 0
    private var domainsWithRulesAppliedSession = Set<String>()

    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "adBlockEnabled") != nil {
                return UserDefaults.standard.bool(forKey: "adBlockEnabled")
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "adBlockEnabled")
        }
    }

    public var currentRuleList: WKContentRuleList? {
        lock.lock()
        defer { lock.unlock() }
        if case .ready(let ruleList) = state {
            return ruleList
        }
        return nil
    }

    public init() {
        loadCosmeticFilterScript()
        loadScriptletFilterScript()
        loadNetworkRuleCountAsync()
        startLoadingRuleListIfNeeded()
        updateRulesOnLaunch()
    }

    
    public static let backspaceScriptSource = """
    window.addEventListener('keydown', function(e) {
        if (e.key === 'Backspace' || e.keyCode === 8) {
            var t = e.target;
            var isEditable = false;
            if (t) {
                var tag = t.tagName ? t.tagName.toUpperCase() : '';
                if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
                    isEditable = true;
                } else if (t.isContentEditable) {
                    isEditable = true;
                } else if (t.closest && t.closest("[contenteditable='true'], [contenteditable='']")) {
                    isEditable = true;
                }
            }
            if (!isEditable) {
                e.preventDefault();
            }
        }
    }, true);
    """

    public static let linkClickScriptSource = """
    window.addEventListener('auxclick', function(e) {
        if (e.button === 1) {
            var a = e.target.closest('a');
            if (a && a.href && !a.href.startsWith('javascript:')) {
                e.preventDefault();
                window.webkit.messageHandlers.openNewTab.postMessage(a.href);
            }
        }
    }, true);
    """

    public static let youTubeScriptletSource = """
    (function() {
        if (window.__isa_youtube_adblock_installed__) return;
        window.__isa_youtube_adblock_installed__ = true;

        function prunePlayerJson(json) {
            if (!json || typeof json !== "object") return json;
            try {
                if ("adPlacements" in json) delete json.adPlacements;
                if ("playerAds" in json) delete json.playerAds;
                if ("adSlots" in json) delete json.adSlots;
                if ("adBreakHeartbeatParams" in json) delete json.adBreakHeartbeatParams;
                if (json.playerResponse && typeof json.playerResponse === "object") {
                    delete json.playerResponse.adPlacements;
                    delete json.playerResponse.playerAds;
                    delete json.playerResponse.adSlots;
                    delete json.playerResponse.adBreakHeartbeatParams;
                }
                if (Array.isArray(json)) {
                    for (var i = 0; i < json.length; i++) {
                        prunePlayerJson(json[i]);
                    }
                }
                if (json.playbackTracking) {
                    delete json.playbackTracking.videostatsAdUrl;
                    delete json.playbackTracking.videostatsPlaybackUrl;
                }
            } catch(e) {}
            return json;
        }

        var origYtInitial = window.ytInitialPlayerResponse;
        Object.defineProperty(window, "ytInitialPlayerResponse", {
            get: function() { return origYtInitial; },
            set: function(val) {
                origYtInitial = prunePlayerJson(val);
            },
            configurable: true,
            enumerable: true
        });
        if (origYtInitial) {
            origYtInitial = prunePlayerJson(origYtInitial);
        }

        var origPlayerResponse = window.playerResponse;
        Object.defineProperty(window, "playerResponse", {
            get: function() { return origPlayerResponse; },
            set: function(val) {
                origPlayerResponse = prunePlayerJson(val);
            },
            configurable: true,
            enumerable: true
        });
        if (origPlayerResponse) {
            origPlayerResponse = prunePlayerJson(origPlayerResponse);
        }

        if (window.fetch) {
            var origFetch = window.fetch;
            window.fetch = function() {
                var args = Array.prototype.slice.call(arguments);
                var url = "";
                if (typeof args[0] === "string") {
                    url = args[0];
                } else if (args[0] && args[0].url) {
                    url = args[0].url;
                }
                var isPlayer = url.indexOf("/player") !== -1 ||
                               url.indexOf("/playlist") !== -1 ||
                               url.indexOf("/watch") !== -1 ||
                               url.indexOf("/get_watch") !== -1;
                var isAdTracking = url.indexOf("/api/stats/ads") !== -1 ||
                                   url.indexOf("/pagead/") !== -1 ||
                                   url.indexOf("/ptracking") !== -1;
                if (isAdTracking) {
                    return Promise.resolve(new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } }));
                }
                return origFetch.apply(this, args).then(function(response) {
                    if (isPlayer) {
                        try {
                            return response.text().then(function(text) {
                                try {
                                    var data = JSON.parse(text);
                                    var pruned = prunePlayerJson(data);
                                    var newBody = JSON.stringify(pruned);
                                    var headers = new Headers(response.headers);
                                    headers.delete("content-length");
                                    return new Response(newBody, {
                                        status: response.status,
                                        statusText: response.statusText,
                                        headers: headers
                                    });
                                } catch(err) {
                                    return new Response(text, {
                                        status: response.status,
                                        statusText: response.statusText,
                                        headers: response.headers
                                    });
                                }
                            });
                        } catch(e) {
                            return response;
                        }
                    }
                    return response;
                });
            };
        }

        if (window.XMLHttpRequest) {
            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
                this.__isa_url = url;
                return origOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                var url = this.__isa_url || "";
                if (url.indexOf("/api/stats/ads") !== -1 || url.indexOf("/pagead/") !== -1) {
                    return;
                }
                return origSend.apply(this, arguments);
            };
        }

        var isHandlingAd = false;
        var userWasMuted = false;

        function handleVideoAds() {
            var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
            var video = document.querySelector("video");
            if (!player && !video) return;

            var isAd = (player && (player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting"))) ||
                       (player && player.getAdState && player.getAdState() > 0) ||
                       (document.querySelector(".video-ads") !== null && document.querySelector(".video-ads").children.length > 0);

            if (isAd && video) {
                if (!isHandlingAd) {
                    userWasMuted = video.muted;
                    isHandlingAd = true;
                }
                video.muted = true;
                if (isFinite(video.duration) && video.duration > 0) {
                    video.currentTime = video.duration;
                }
                video.playbackRate = 16.0;

                if (player && typeof player.skipAd === "function") {
                    try { player.skipAd(); } catch(e) {}
                }

                var skipSelectors = [
                    ".ytp-skip-ad-button",
                    ".ytp-ad-skip-button",
                    ".ytp-ad-skip-button-modern",
                    ".ytp-ad-skip-button-slot button",
                    "button.ytp-ad-skip-button-modern",
                    "[id^='skip-button:']",
                    ".ytp-ad-overlay-close-button",
                    "button.ytp-ad-overlay-close-button"
                ];
                for (var s = 0; s < skipSelectors.length; s++) {
                    var btns = document.querySelectorAll(skipSelectors[s]);
                    for (var b = 0; b < btns.length; b++) {
                        try { btns[b].click(); } catch(e) {}
                    }
                }
            } else if (!isAd && isHandlingAd && video) {
                isHandlingAd = false;
                video.playbackRate = 1.0;
                if (!userWasMuted) {
                    video.muted = false;
                }
            }

            var dialogs = document.querySelectorAll("tp-yt-paper-dialog");
            for (var d = 0; d < dialogs.length; d++) {
                var dlg = dialogs[d];
                if (dlg.querySelector("ytd-enforcement-message-view-model") || (dlg.textContent && dlg.textContent.indexOf("Ad blocker") !== -1)) {
                    try {
                        dlg.remove();
                        var backdrops = document.querySelectorAll(".iron-overlay-backdrop");
                        for (var bp = 0; bp < backdrops.length; bp++) {
                            backdrops[bp].remove();
                        }
                        if (video && video.paused) {
                            video.play();
                        }
                    } catch(e) {}
                }
            }
        }

        setInterval(handleVideoAds, 50);

        window.addEventListener("yt-navigate-finish", function() {
            isHandlingAd = false;
            if (window.ytInitialPlayerResponse) {
                window.ytInitialPlayerResponse = prunePlayerJson(window.ytInitialPlayerResponse);
            }
            handleVideoAds();
        });

        if (window.MutationObserver) {
            var obs = new MutationObserver(function() {
                handleVideoAds();
            });
            obs.observe(document.documentElement || document, { childList: true, subtree: true });
        }
    })();
    """


    public static func apply(to configuration: WKWebViewConfiguration, host: String? = nil) {
        shared.apply(to: configuration, host: host)
    }

    public func apply(to configuration: WKWebViewConfiguration, host: String? = nil) {
        if !isEnabled ||
           ProcessInfo.processInfo.environment["ISA_DISABLE_ADBLOCK"] == "1" ||
           ProcessInfo.processInfo.arguments.contains("--no-adblock") {
            return
        }

        startLoadingRuleListIfNeeded()

        if ProcessInfo.processInfo.environment["ISA_DISABLE_COSMETIC"] != "1",
           let cosmeticScript = cosmeticUserScript(for: host) {
            configuration.userContentController.addUserScript(cosmeticScript)
        }

        if ProcessInfo.processInfo.environment["ISA_DISABLE_SCRIPTLETS"] != "1",
           let scriptletScript = scriptletUserScript(for: host) {
            configuration.userContentController.addUserScript(scriptletScript)
        }

        if ProcessInfo.processInfo.environment["ISA_DISABLE_CONTENT_RULES"] == "1" ||
           ProcessInfo.processInfo.arguments.contains("--no-content-rules") {
            return
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

    public func updateUserScripts(for webView: WKWebView, host: String) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        let backspaceScript = WKUserScript(source: Self.backspaceScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        ucc.addUserScript(backspaceScript)
        let linkClickScript = WKUserScript(source: Self.linkClickScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(linkClickScript)
        let mediaScript = WKUserScript(source: Tab.mediaScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(mediaScript)
        let swipeScript = WKUserScript(source: Swipe.watch, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(swipeScript)

        if isEnabled &&
           ProcessInfo.processInfo.environment["ISA_DISABLE_ADBLOCK"] != "1" &&
           !ProcessInfo.processInfo.arguments.contains("--no-adblock") {
            if ProcessInfo.processInfo.environment["ISA_DISABLE_COSMETIC"] != "1",
               let cosmetic = cosmeticUserScript(for: host) {
                ucc.addUserScript(cosmetic)
            }
            if ProcessInfo.processInfo.environment["ISA_DISABLE_SCRIPTLETS"] != "1",
               let scriptlet = scriptletUserScript(for: host) {
                ucc.addUserScript(scriptlet)
            }
        }
    }

    public func cosmeticCSS(for host: String?) -> String {
        guard let host = host?.lowercased(), !host.isEmpty else { return "" }
        let parts = host.split(separator: ".")
        var allSelectors: [String] = []
        let limit = parts.count > 1 ? parts.count - 1 : parts.count
        lock.lock()
        for i in 0..<limit {
            let candidate = parts[i...].joined(separator: ".")
            if let sel = cosmeticRulesByDomain[candidate], !sel.isEmpty {
                allSelectors.append(sel)
            }
        }
        lock.unlock()

        if host.contains("youtube.com") {
            let youtubeDefaults = [
                "#masthead-ad",
                "ytd-ad-slot-renderer",
                "ytd-rich-item-renderer:has(> #content > ytd-ad-slot-renderer)",
                "ytd-rich-item-renderer:has(> ytd-ad-slot-renderer)",
                "ytd-promoted-sparkles-web-renderer",
                "ytd-promoted-video-renderer",
                "ytd-display-ad-renderer",
                "ytd-statement-banner-renderer",
                "ytd-banner-promo-renderer",
                "ytd-in-feed-ad-layout-renderer",
                "ytd-companion-ad-renderer",
                "ytd-action-companion-ad-renderer",
                "#player-ads",
                ".video-ads",
                ".ytp-ad-module",
                ".ytp-ad-overlay-container",
                ".ytp-ad-message-container",
                ".ytp-ad-player-overlay",
                ".ytp-ad-action-interstitial",
                ".ytp-ad-image-overlay",
                ".ytp-ad-text-overlay",
                "yt-mealbar-promo-renderer",
                "ytd-engagement-panel-section-list-renderer[target-id=\"engagement-panel-ads\"]",
                "tp-yt-paper-dialog:has(ytd-enforcement-message-view-model)",
                "ytd-enforcement-message-view-model"
            ]
            allSelectors.append(contentsOf: youtubeDefaults)
        }

        let proceduralIndicators = [
            ":has-text(",
            ":upward(",
            ":xpath(",
            ":matches-css(",
            ":min-text-length(",
            ":watch-attr("
        ]

        let validSelectors = allSelectors
            .flatMap { $0.components(separatedBy: ",\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { sel in
                guard !sel.isEmpty else { return false }
                for p in proceduralIndicators {
                    if sel.contains(p) { return false }
                }
                return true
            }

        guard !validSelectors.isEmpty else { return "" }
        return validSelectors.map { "\($0) { display: none !important; }" }.joined(separator: "\n")
    }

    public func cosmeticUserScript(for host: String?) -> WKUserScript? {
        let css = cosmeticCSS(for: host)
        guard !css.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: [css]),
              let jsonArray = String(data: data, encoding: .utf8),
              jsonArray.hasPrefix("[\"") && jsonArray.hasSuffix("\"]") else {
            return nil
        }
        let escapedCSS = String(jsonArray.dropFirst().dropLast())
        let jsSource = """
        (function() {
            if (window.__isa_cosmetic_applied__) return;
            window.__isa_cosmetic_applied__ = true;
            var style = document.createElement("style");
            style.setAttribute("type", "text/css");
            style.setAttribute("data-isa-adblock", "cosmetic");
            style.textContent = \(escapedCSS);
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
        return WKUserScript(source: jsSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    public func scriptletUserScript(for host: String?) -> WKUserScript? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        let parts = host.split(separator: ".")
        var snippetsForHost: [String] = []
        let limit = parts.count > 1 ? parts.count - 1 : parts.count
        lock.lock()
        for i in 0..<limit {
            let candidate = parts[i...].joined(separator: ".")
            if let list = scriptletsByDomain[candidate] {
                snippetsForHost.append(contentsOf: list)
            }
        }
        lock.unlock()

        if host.contains("youtube.com") {
            snippetsForHost.insert(Self.youTubeScriptletSource, at: 0)
        }

        guard !snippetsForHost.isEmpty else { return nil }

        var snippetGlobalId = 0
        var body = ""
        for snippet in snippetsForHost {
            snippetGlobalId += 1
            body += """
                if (!window.__isa_scriptlets_run__[\(snippetGlobalId)]) {
                    window.__isa_scriptlets_run__[\(snippetGlobalId)] = true;
                    try {
                        \(snippet)
                    } catch (e) {}
                }
            """
        }

        let jsSource = """
        (function() {
            if (window.__isa_scriptlets_applied__) return;
            window.__isa_scriptlets_applied__ = true;
            window.__isa_scriptlets_run__ = window.__isa_scriptlets_run__ || {};
            \(body)
        })();
        """
        return WKUserScript(source: jsSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static var localRulesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("isa/rules", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var rulesBaseURL: URL {
        if let custom = ProcessInfo.processInfo.environment["ISA_RULES_URL"], let url = URL(string: custom) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/drunkardleo-10/isa/master/rules/")!
    }

    private static var hasUpdatedThisLaunch = false
    private static let updateQueue = DispatchQueue(label: "com.isa.adblock.updater")

    private static func candidateURLs(for filename: String) -> [URL] {
        let list: [URL?] = [
            Self.localRulesDirectory.appendingPathComponent(filename),
            Bundle.main.url(forResource: (filename as NSString).deletingPathExtension, withExtension: "json"),
            Bundle.main.url(forResource: (filename as NSString).deletingPathExtension, withExtension: "json", subdirectory: "rules"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(filename)"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/rules/\(filename)"),
            URL(fileURLWithPath: "rules/\(filename)"),
            Bundle.main.bundleURL.appendingPathComponent("rules/\(filename)")
        ]
        return list.compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func loadCosmeticFilterScript() {
        guard let url = Self.candidateURLs(for: "cosmetic-filters.json").first,
              let jsonString = try? String(contentsOf: url, encoding: .utf8),
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            PerformanceMonitor.shared.log(event: "AdBlock", details: "Cosmetic filters file not found or empty")
            return
        }

        self.lock.lock()
        self.cosmeticRulesByDomain = dict
        var count = 0
        for (_, selectors) in dict {
            count += selectors.components(separatedBy: ",\n").count
        }
        self.totalCosmeticSelectorsCount = count
        self.lock.unlock()
        PerformanceMonitor.shared.log(event: "AdBlock", details: "Cosmetic filter store loaded successfully (\(count) selectors across \(dict.count) domains)")
    }

    private func loadScriptletFilterScript() {
        guard let url = Self.candidateURLs(for: "scriptlets.json").first,
              let jsonString = try? String(contentsOf: url, encoding: .utf8),
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            PerformanceMonitor.shared.log(event: "AdBlock", details: "Scriptlets file not found or empty")
            return
        }

        self.lock.lock()
        self.scriptletsByDomain = dict
        var totalSnippets = 0
        for (_, snippets) in dict {
            totalSnippets += snippets.count
        }
        self.totalScriptletSnippetsCount = totalSnippets
        self.lock.unlock()
        PerformanceMonitor.shared.log(event: "AdBlock", details: "Scriptlet filter store loaded successfully (\(totalSnippets) snippets across \(dict.count) domains)")
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
        guard let url = Self.candidateURLs(for: "content-blocker.json").first else {
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
            guard let url = Self.candidateURLs(for: "content-blocker.json").first,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }

            self?.lock.lock()
            self?.networkRuleCount = jsonArray.count
            self?.lock.unlock()
        }
    }

    public func updateRulesOnLaunch() {
        guard isEnabled,
              ProcessInfo.processInfo.environment["ISA_DISABLE_ADBLOCK"] != "1",
              !ProcessInfo.processInfo.arguments.contains("--no-adblock")
        else { return }

        Self.updateQueue.async { [weak self] in
            guard !Self.hasUpdatedThisLaunch else { return }
            Self.hasUpdatedThisLaunch = true

            Task { [weak self] in
                guard let self = self else { return }
                await self.performBackgroundRulesUpdate()
            }
        }
    }

    private func performBackgroundRulesUpdate() async {
        let baseURL = Self.rulesBaseURL
        let localDir = Self.localRulesDirectory

        let cosmeticUpdated = await fetchRuleFile(
            named: "cosmetic-filters.json",
            from: baseURL,
            to: localDir
        ) { data in
            (try? JSONSerialization.jsonObject(with: data)) is [String: String]
        }

        if cosmeticUpdated {
            loadCosmeticFilterScript()
        }

        let scriptletsUpdated = await fetchRuleFile(
            named: "scriptlets.json",
            from: baseURL,
            to: localDir
        ) { data in
            (try? JSONSerialization.jsonObject(with: data)) is [String: [String]]
        }

        if scriptletsUpdated {
            loadScriptletFilterScript()
        }

        let contentBlockerUpdated = await fetchRuleFile(
            named: "content-blocker.json",
            from: baseURL,
            to: localDir
        ) { data in
            (try? JSONSerialization.jsonObject(with: data)) is [[String: Any]]
        }

        if contentBlockerUpdated {
            recompileRuleList(from: localDir.appendingPathComponent("content-blocker.json"))
        }
    }

    private func fetchRuleFile(
        named filename: String,
        from baseURL: URL,
        to localDirectory: URL,
        validator: (Data) -> Bool
    ) async -> Bool {
        guard let remoteURL = URL(string: filename, relativeTo: baseURL) else { return false }
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 25

        let targetURL = localDirectory.appendingPathComponent(filename)
        let etagKey = "isa.adblock.etag.\(filename)"
        if let savedETag = UserDefaults.standard.string(forKey: etagKey),
           FileManager.default.fileExists(atPath: targetURL.path) {
            request.setValue(savedETag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }

        if http.statusCode == 304 {
            PerformanceMonitor.shared.log(event: "AdBlockUpdate", details: "\(filename) is up-to-date (304 Not Modified)")
            return false
        }

        guard http.statusCode == 200, !data.isEmpty, validator(data) else {
            return false
        }

        let tempURL = targetURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                UserDefaults.standard.set(etag, forKey: etagKey)
            }
            PerformanceMonitor.shared.log(event: "AdBlockUpdate", details: "\(filename) updated successfully (\(data.count) bytes)")
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    private func recompileRuleList(from fileURL: URL) {
        guard let store = WKContentRuleListStore.default(),
              let jsonString = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }

        let startTime = Date()
        PerformanceMonitor.shared.log(event: "AdBlockCompile", details: "Recompiling updated content blocker rules...")

        store.compileContentRuleList(
            forIdentifier: Self.ruleListIdentifier,
            encodedContentRuleList: jsonString
        ) { [weak self] ruleList, error in
            guard let self = self else { return }
            if let ruleList = ruleList {
                let duration = Date().timeIntervalSince(startTime)
                PerformanceMonitor.shared.log(event: "AdBlockCompile", details: "Updated rule list compiled in \(String(format: "%.2f", duration))s")
                self.transition(to: .ready(ruleList))
                self.loadNetworkRuleCountAsync()
            } else if let error = error {
                PerformanceMonitor.shared.log(event: "AdBlockError", details: "Failed to compile updated rules: \(error.localizedDescription)")
            }
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

    public var totalScriptletsCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalScriptletSnippetsCount
    }

    public static var totalScriptletsCount: Int {
        shared.totalScriptletsCount
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

    public func removeCosmeticCSS(from webView: WKWebView) {
        let js = """
        (function() {
            window.__isa_cosmetic_applied__ = false;
            var styles = document.querySelectorAll('style[data-isa-adblock="cosmetic"]');
            for (var i = 0; i < styles.length; i++) {
                styles[i].remove();
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    public func injectCosmeticCSS(into webView: WKWebView, host: String?) {
        guard isEnabled else { return }
        let css = cosmeticCSS(for: host)
        guard !css.isEmpty else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: [css]),
              let jsonArray = String(data: data, encoding: .utf8),
              jsonArray.hasPrefix("[\"") && jsonArray.hasSuffix("\"]") else {
            return
        }
        let escapedCSS = String(jsonArray.dropFirst().dropLast())
        let js = """
        (function() {
            if (window.__isa_cosmetic_applied__) return;
            var style = document.createElement("style");
            style.setAttribute("type", "text/css");
            style.setAttribute("data-isa-adblock", "cosmetic");
            style.textContent = \(escapedCSS);
            var target = document.head || document.documentElement;
            if (target) {
                target.appendChild(style);
                window.__isa_cosmetic_applied__ = true;
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
