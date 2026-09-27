import SwiftUI
import AppKit
import ObjectiveC

struct WindowAccessor: NSViewRepresentable {
    let theme: AppTheme
    let transparency: Double

    init(theme: AppTheme, transparency: Double = 0.0) {
        self.theme = theme
        self.transparency = transparency
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyTheme(to: view)
            setupTranslucency(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyTheme(to: nsView)
            setupTranslucency(for: nsView)
        }
    }

    private func applyTheme(to view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        disableWindowDrag(in: window)
        window.makeKeyAndOrderFront(nil)
        switch theme {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func setupTranslucency(for view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear

        let effectIdentifier = NSUserInterfaceItemIdentifier("WindowTranslucencyEffectView")
        let effectView: NSVisualEffectView
        if let existing = window.contentView?.superview?.subviews.first(where: { $0.identifier == effectIdentifier }) as? NSVisualEffectView {
            effectView = existing
        } else if let existing = window.contentView?.subviews.first(where: { $0.identifier == effectIdentifier }) as? NSVisualEffectView {
            effectView = existing
        } else {
            let vev = NSVisualEffectView()
            vev.identifier = effectIdentifier
            vev.material = .underWindowBackground
            vev.blendingMode = .behindWindow
            vev.state = .active
            if let contentView = window.contentView, let superview = contentView.superview {
                vev.frame = superview.bounds
                vev.autoresizingMask = [.width, .height]
                superview.addSubview(vev, positioned: .below, relativeTo: contentView)
            } else if let contentView = window.contentView {
                vev.frame = contentView.bounds
                vev.autoresizingMask = [.width, .height]
                contentView.addSubview(vev, positioned: .below, relativeTo: nil)
            }
            effectView = vev
        }
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
    }

    private func disableWindowDrag(in window: NSWindow) {
        let block: @convention(block) (AnyObject) -> Bool = { _ in false }
        let imp = imp_implementationWithBlock(block)
        let sel = #selector(getter: NSView.mouseDownCanMoveWindow)
        if let contentView = window.contentView,
           let method = class_getInstanceMethod(type(of: contentView), sel) {
            method_setImplementation(method, imp)
        }
        if let frameView = window.contentView?.superview {
            disableWindowDragRecursively(in: frameView, sel: sel, imp: imp)
        }
    }

    private func disableWindowDragRecursively(in view: NSView, sel: Selector, imp: IMP) {
        if String(describing: type(of: view)).contains("Titlebar") {
            if let method = class_getInstanceMethod(type(of: view), sel) {
                method_setImplementation(method, imp)
            }
        }
        for sub in view.subviews {
            disableWindowDragRecursively(in: sub, sel: sel, imp: imp)
        }
    }
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {}

    final class DragNSView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                guard let window = self.window, window.isMovable else { return }
                window.performDrag(with: event)
            }
        }
    }
}

struct NonDraggableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NonDraggableNSView {
        NonDraggableNSView()
    }

    func updateNSView(_ nsView: NonDraggableNSView, context: Context) {}

    final class NonDraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            return false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }
    }
}
