import Foundation
import WebKit
import AppKit

enum InspectorHelper {
    static func enableDeveloperExtras(_ preferences: WKPreferences, on: Bool = true) {
        let set = NSSelectorFromString("_setDeveloperExtrasEnabled:")
        guard preferences.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, on)
    }

    static func isInspector(_ view: NSView) -> Bool {
        String(describing: type(of: view)).hasPrefix("WKInspector")
    }

    static func isInspecting(webView: WKWebView?) -> Bool {
        guard let webView = webView else { return false }
        let get = NSSelectorFromString("_inspector")
        guard webView.responds(to: get),
              let inspector = webView.perform(get)?.takeUnretainedValue() as? NSObject
        else { return false }
        let visible = NSSelectorFromString("isVisible")
        guard inspector.responds(to: visible) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(inspector.method(for: visible), to: Getter.self)(inspector, visible)
    }

    static func inspector(for webView: WKWebView?) -> NSObject? {
        guard let webView = webView else { return nil }
        let get = NSSelectorFromString("_inspector")
        guard webView.responds(to: get) else { return nil }
        return webView.perform(get)?.takeUnretainedValue() as? NSObject
    }

    static func send(_ inspector: NSObject, _ name: String) {
        let selector = NSSelectorFromString(name)
        guard inspector.responds(to: selector) else { return }
        inspector.perform(selector)
    }

    static func asks(_ inspector: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard inspector.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(inspector.method(for: selector), to: Getter.self)(inspector, selector)
    }
}

extension Tab {
    func toggleInspector() {
        guard let inspector = inspector() else { return }
        if InspectorHelper.asks(inspector, "isVisible") {
            InspectorHelper.send(inspector, "close")
        } else {
            InspectorHelper.send(inspector, "show")
        }
    }

    func showConsole() {
        guard let inspector = inspector() else { return }
        InspectorHelper.send(inspector, "showConsole")
    }

    func inspectElement() {
        guard let inspector = inspector() else { return }
        if !InspectorHelper.asks(inspector, "isVisible") {
            InspectorHelper.send(inspector, "show")
        }
        InspectorHelper.send(inspector, "toggleElementSelection")
    }

    func inspector() -> NSObject? {
        guard canInspect else { return nil }
        let web = ensureWebView()
        return InspectorHelper.inspector(for: web)
    }
}

extension BrowserViewModel {
    func toggleInspector() {
        wakeTabIfNeeded(activeTab)
        activeTab.toggleInspector()
    }

    func showConsole() {
        wakeTabIfNeeded(activeTab)
        activeTab.showConsole()
    }

    func inspectElement() {
        wakeTabIfNeeded(activeTab)
        activeTab.inspectElement()
    }
}
