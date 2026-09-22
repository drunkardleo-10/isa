import SwiftUI
import AppKit
import ObjectiveC

struct ContentView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Namespace private var tabNamespace
    @State private var draggingTabId: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var dragInitialIndex: Int? = nil
    @State private var dragTargetIndex: Int? = nil
    @State private var isShieldPopoverPresented: Bool = false
    @State private var isDownloadsPopoverPresented: Bool = false
    @State private var keyMonitor: Any? = nil
    @ObservedObject private var downloadManager: DownloadManager = DownloadManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                topBar
                    .zIndex(10)

                ZStack(alignment: .bottom) {
                    Color(nsColor: .windowBackgroundColor)

                    ForEach(viewModel.tabs) { tab in
                        if !tab.isNewTabState || tab.webView != nil || tab.isSleeping {
                            ZStack {
                                WebView(tab: tab)
                                if let error = tab.pageError {
                                    PageCrashErrorView(error: error) {
                                        tab.reload()
                                    }
                                }
                            }
                            .opacity(tab.id == viewModel.selectedTabId && !tab.isNewTabState ? 1 : 0)
                            .allowsHitTesting(tab.id == viewModel.selectedTabId && !tab.isNewTabState && !tab.isAddressOverlayPresented && !isShieldPopoverPresented && !isDownloadsPopoverPresented)
                        }
                    }

                    ActiveTabOverlayView(tab: viewModel.activeTab, viewModel: viewModel)

                    FindBarOverlay(tab: viewModel.activeTab)
                }
            }

            if isShieldPopoverPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.10)) {
                            isShieldPopoverPresented = false
                        }
                    }
                    .zIndex(90)

                AdBlockStatusPopover(viewModel: viewModel)
                    .padding(.top, 42)
                    .padding(.trailing, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity)
                    ))
                    .zIndex(100)
            }

            if isDownloadsPopoverPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.10)) {
                            isDownloadsPopoverPresented = false
                        }
                    }
                    .zIndex(90)

                DownloadsPopoverView(downloadManager: downloadManager)
                    .padding(.top, 42)
                    .padding(.trailing, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity)
                    ))
                    .zIndex(100)
            }
        }
        .onExitCommand {
            if viewModel.activeTab.isFindPresented {
                viewModel.hideFindInPage()
            } else if isDownloadsPopoverPresented {
                withAnimation(.easeOut(duration: 0.10)) {
                    isDownloadsPopoverPresented = false
                }
            } else if isShieldPopoverPresented {
                withAnimation(.easeOut(duration: 0.10)) {
                    isShieldPopoverPresented = false
                }
            }
        }
        .onAppear {
            PerformanceMonitor.shared.log(event: "WindowReady", details: "Window content rendered on screen")
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let chars = event.charactersIgnoringModifiers?.lowercased()
                    let isCmd = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
                    let isF = (chars == "f") || event.keyCode == 3
                    let isG = (chars == "g") || event.keyCode == 5

                    if isCmd && isF && !flags.contains(.shift) {
                        viewModel.toggleFindInPage()
                        return nil
                    }
                    if isCmd && isG {
                        if flags.contains(.shift) {
                            viewModel.findPreviousInPage()
                        } else {
                            viewModel.findNextInPage()
                        }
                        return nil
                    }
                    return event
                }
            }
        }
        .onReceive(downloadManager.objectWillChange) { _ in }
        .onReceive(viewModel.activeTab.objectWillChange) { _ in }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor(theme: viewModel.theme))
        .background(
            Group {
                ForEach(1...9, id: \.self) { num in
                    Button("") {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            viewModel.selectTabNumber(num)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(num)")), modifiers: .command)
                }

                Button("") {
                    viewModel.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 6) {
            WindowDragHandle()
                .frame(width: 78, height: 38)

            navigationBar

            tabStripView

            Button(action: {
                PerformanceMonitor.shared.log(event: "Click", details: "AdBlock shield popover toggle")
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    isShieldPopoverPresented.toggle()
                    if isShieldPopoverPresented {
                        isDownloadsPopoverPresented = false
                    }
                }
            }) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isShieldPopoverPresented ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ad & Tracker Protection")

            if downloadManager.shouldShowTopBarButton {
                Button(action: {
                    PerformanceMonitor.shared.log(event: "Click", details: "Downloads popover toggle")
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                        isDownloadsPopoverPresented.toggle()
                        if isDownloadsPopoverPresented {
                            downloadManager.hasUnreadCompletion = false
                            isShieldPopoverPresented = false
                        }
                    }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDownloadsPopoverPresented ? .primary : (downloadManager.hasActiveDownloads ? .accentColor : .secondary))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())

                        if downloadManager.hasActiveDownloads {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .offset(x: -3, y: 5)
                        } else if downloadManager.hasUnreadCompletion {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .offset(x: -3, y: 5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Downloads")
            }

            AnimatedThemeToggle(viewModel: viewModel)
        }
        .frame(height: 38)
        .padding(.trailing, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(NonDraggableBackground())
    }

    private var navigationBar: some View {
        HStack(spacing: 3) {
            NavButton(icon: "back", tooltip: "Back (⌘[)", disabled: !viewModel.activeTab.canGoBack) {
                viewModel.goBackActiveTab()
            }
            NavButton(icon: "forward", tooltip: "Forward (⌘])", disabled: !viewModel.activeTab.canGoForward) {
                viewModel.goForwardActiveTab()
            }
            NavButton(icon: "reload", tooltip: "Reload (⌘R)", disabled: viewModel.activeTab.isNewTabState) {
                viewModel.reloadActiveTab()
            }
            NavButton(icon: "home", tooltip: "Home", disabled: viewModel.activeTab.isNewTabState) {
                viewModel.goHomeActiveTab()
            }
        }
    }

    private var tabStripView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let tabCount = viewModel.tabs.count
            let spacing: CGFloat = tabCount > 60 ? 1 : (tabCount > 25 ? 1.5 : (tabCount > 12 ? 2 : 4))
            let plusButtonWidth: CGFloat = 26
            let maxTabWidth: CGFloat = 200
            let minTabWidth: CGFloat = 6
            let totalSpacing = CGFloat(max(0, tabCount - 1)) * spacing
            let availableForTabs = max(0, availableWidth - plusButtonWidth - totalSpacing - 4)
            let calculatedTabWidth = tabCount > 0 ? (availableForTabs / CGFloat(tabCount)) : maxTabWidth
            let tabWidth = min(maxTabWidth, max(minTabWidth, calculatedTabWidth))
            let totalContentWidth = (CGFloat(tabCount) * tabWidth) + totalSpacing + plusButtonWidth + 4
            let isOverflowing = totalContentWidth > availableWidth

            HStack(spacing: 0) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .center, spacing: spacing) {
                            ForEach(Array(viewModel.tabs.enumerated()), id: \.element.id) { index, tab in
                                let offset = tabOffset(for: tab, index: index, tabWidth: tabWidth, spacing: spacing)
                                TabPillView(
                                    tab: tab,
                                    viewModel: viewModel,
                                    isSelected: tab.id == viewModel.selectedTabId,
                                    tabNamespace: tabNamespace,
                                    tabWidth: tabWidth,
                                    isBeingDragged: draggingTabId == tab.id,
                                    isAnyTabDragging: draggingTabId != nil,
                                    onDragStarted: {
                                        handleTabDragStarted(tab: tab)
                                    },
                                    onDragChanged: { translationX in
                                        handleTabDragChanged(tab: tab, translationX: translationX, tabWidth: tabWidth, spacing: spacing)
                                    },
                                    onDragEnded: {
                                        handleTabDragEnded()
                                    },
                                    onSelect: {
                                        if tab.id == viewModel.selectedTabId && !tab.isNewTabState {
                                            viewModel.focusAddressBar()
                                        } else {
                                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                                viewModel.selectTab(id: tab.id)
                                            }
                                        }
                                    }
                                )
                                .id(tab.id)
                                .offset(x: offset)
                                .zIndex(draggingTabId == tab.id ? 10 : 1)
                                .animation(draggingTabId == tab.id ? nil : .spring(response: 0.22, dampingFraction: 0.85), value: offset)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                                    removal: .scale(scale: 0.85).combined(with: .opacity)
                                ))
                            }

                            NewTabButton {
                                PerformanceMonitor.shared.log(event: "Click", details: "New Tab (+) button")
                                viewModel.createNewTab()
                            }
                        }
                        .padding(.trailing, 2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: viewModel.tabs.count)
                    }
                    .clipped()
                    .background(NonDraggableBackground())
                    .frame(width: isOverflowing ? availableWidth : min(totalContentWidth, availableWidth), alignment: .leading)
                    .onChange(of: viewModel.selectedTabId) { _, newId in
                        if draggingTabId == nil {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollProxy.scrollTo(newId, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: viewModel.tabs.count) { _, _ in
                        if let lastTab = viewModel.tabs.last, viewModel.selectedTabId == lastTab.id {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollProxy.scrollTo(lastTab.id, anchor: .trailing)
                            }
                        }
                    }
                    .onChange(of: viewModel.tabs.map { $0.id }) { _, ids in
                        if let dragging = draggingTabId, !ids.contains(dragging) {
                            draggingTabId = nil
                            dragInitialIndex = nil
                            dragTargetIndex = nil
                            dragOffset = 0
                        }
                    }
                }

                if !isOverflowing {
                    NonDraggableBackground()
                        .frame(maxWidth: .infinity, maxHeight: 38)
                }
            }
            .frame(width: availableWidth, height: 38, alignment: .leading)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: 38)
        .clipped()
    }

    private func handleTabDragStarted(tab: Tab) {
        guard let index = viewModel.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        NSApp.keyWindow?.isMovable = false
        draggingTabId = tab.id
        dragInitialIndex = index
        dragTargetIndex = index
        dragOffset = 0
    }

    private func handleTabDragChanged(tab: Tab, translationX: CGFloat, tabWidth: CGFloat, spacing: CGFloat) {
        guard draggingTabId == tab.id, let initialIndex = dragInitialIndex else { return }
        dragOffset = translationX
        let pitch = tabWidth + spacing
        guard pitch > 0 else { return }
        let shift = Int(round(translationX / pitch))
        let newTarget = max(0, min(viewModel.tabs.count - 1, initialIndex + shift))
        if newTarget != dragTargetIndex {
            dragTargetIndex = newTarget
        }
    }

    private func handleTabDragEnded() {
        NSApp.keyWindow?.isMovable = true
        guard let draggedId = draggingTabId,
              let initial = dragInitialIndex,
              let target = dragTargetIndex else {
            draggingTabId = nil
            dragInitialIndex = nil
            dragTargetIndex = nil
            dragOffset = 0
            return
        }

        if initial != target {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.moveTab(from: initial, to: target)
                draggingTabId = nil
                dragInitialIndex = nil
                dragTargetIndex = nil
                dragOffset = 0
            }
        } else {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                dragOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                if self.draggingTabId == draggedId {
                    self.draggingTabId = nil
                    self.dragInitialIndex = nil
                    self.dragTargetIndex = nil
                    self.dragOffset = 0
                }
            }
        }

        if viewModel.selectedTabId != draggedId {
            viewModel.selectTab(id: draggedId)
        }
    }

    private func tabOffset(for tab: Tab, index: Int, tabWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        if tab.id == draggingTabId {
            return dragOffset
        }
        guard let initial = dragInitialIndex, let target = dragTargetIndex, initial != target else {
            return 0
        }
        let pitch = tabWidth + spacing
        if initial < target {
            if index > initial && index <= target {
                return -pitch
            }
        } else if initial > target {
            if index >= target && index < initial {
                return pitch
            }
        }
        return 0
    }
}

struct WindowAccessor: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyTheme(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyTheme(to: nsView)
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

struct TabPillInteractionView: NSViewRepresentable {
    let tabWidth: CGFloat
    let showsCloseButton: Bool
    let showsSpeakerButton: Bool
    let onDragStarted: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onSelect: () -> Void
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> PillNSView {
        let view = PillNSView()
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: PillNSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ view: PillNSView) {
        view.tabWidth = tabWidth
        view.showsCloseButton = showsCloseButton
        view.showsSpeakerButton = showsSpeakerButton
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onSelect = onSelect
        view.onMiddleClick = onMiddleClick
    }

    final class PillNSView: NSView {
        var tabWidth: CGFloat = 100
        var showsCloseButton: Bool = false
        var showsSpeakerButton: Bool = false
        var onDragStarted: (() -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?
        var onSelect: (() -> Void)?
        var onMiddleClick: (() -> Void)?

        private var startLocation: NSPoint = .zero
        private var isDragging: Bool = false

        override var mouseDownCanMoveWindow: Bool {
            return false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }

        override var intrinsicContentSize: NSSize {
            return NSSize(width: NSView.noIntrinsicMetric, height: 30)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let hit = super.hitTest(point) else { return nil }
            let localPoint = superview != nil ? convert(point, from: superview) : point
            var interactiveTrailingWidth: CGFloat = 0
            if showsCloseButton && showsSpeakerButton {
                interactiveTrailingWidth = 42
            } else if showsCloseButton || showsSpeakerButton {
                interactiveTrailingWidth = 24
            }
            if interactiveTrailingWidth > 0 && localPoint.x >= (bounds.width - interactiveTrailingWidth) {
                return nil
            }
            return hit
        }

        override func mouseDown(with event: NSEvent) {
            startLocation = event.locationInWindow
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            let current = event.locationInWindow
            let deltaX = current.x - startLocation.x
            let deltaY = current.y - startLocation.y
            let dist = hypot(deltaX, deltaY)

            if dist >= 3 {
                if !isDragging {
                    isDragging = true
                    window?.isMovable = false
                    onDragStarted?()
                }
                onDragChanged?(deltaX)
            }
        }

        override func mouseUp(with event: NSEvent) {
            window?.isMovable = true
            if isDragging {
                isDragging = false
                onDragEnded?()
            } else {
                onSelect?()
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil && isDragging {
                window?.isMovable = true
                isDragging = false
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                onMiddleClick?()
            } else {
                super.otherMouseDown(with: event)
            }
        }
    }
}

struct GooeyBridge: Shape {
    var distance: CGFloat

    var animatableData: CGFloat {
        get { distance }
        set { distance = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 22.0
        guard distance > 0.5 else { return path }

        let maxDist: CGFloat = 46.0
        let t = min(distance / maxDist, 1.0)
        guard t < 0.99 else { return path }

        let cy = r

        let attachHalf = r * pow(1.0 - t, 0.35)
        let waistHalf = attachHalf * pow(1.0 - t, 0.7) * 0.55
        guard attachHalf > 0.8 else { return path }

        let ang1 = asin(min(1.0, attachHalf / r))
        let lx = r + r * cos(ang1)

        let ang2 = asin(min(1.0, attachHalf / r))
        let rx = (distance + r) - r * cos(ang2)

        let midX = (lx + rx) / 2.0

        path.move(to: CGPoint(x: lx, y: cy - attachHalf))
        path.addCurve(
            to: CGPoint(x: rx, y: cy - attachHalf),
            control1: CGPoint(x: midX, y: cy - waistHalf),
            control2: CGPoint(x: midX, y: cy - waistHalf)
        )
        path.addLine(to: CGPoint(x: rx, y: cy + attachHalf))
        path.addCurve(
            to: CGPoint(x: lx, y: cy + attachHalf),
            control1: CGPoint(x: midX, y: cy + waistHalf),
            control2: CGPoint(x: midX, y: cy + waistHalf)
        )
        path.closeSubpath()
        return path
    }
}

struct ActiveTabOverlayView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var viewModel: BrowserViewModel
    @FocusState private var isFocused: Bool
    @State private var addressInput: String = ""
    @State private var eventMonitor: Any? = nil
    @State private var suggestions: [SuggestionItem] = []
    @State private var selectedSuggestionIndex: Int = -1
    @State private var isAddShortcutPresented: Bool = false
    @State private var editingShortcut: ShortcutItem? = nil
    @State private var isExpanded: Bool = true
    @State private var expandProgress: CGFloat = 1.0
    @State private var isIdleHovered: Bool = false
    @State private var inactivityTask: Task<Void, Never>? = nil

    private var pillOffset: CGFloat {
        expandProgress * 52.0
    }

    private var currentPillWidth: CGFloat {
        260.0 + 168.0 * expandProgress
    }

    private var containerWidth: CGFloat {
        pillOffset + currentPillWidth
    }

    var body: some View {
        if tab.isNewTabState || tab.isAddressOverlayPresented {
            ZStack {
                if tab.isAddressOverlayPresented && !tab.isNewTabState {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture {
                            viewModel.dismissAddressBar()
                        }
                } else if tab.isNewTabState {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isAddShortcutPresented {
                                dismissOrCollapseSearchBar()
                            }
                        }
                }

                VStack(spacing: 4) {
                    Spacer()
                        .frame(height: 140)

                    ZStack(alignment: .leading) {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)

                        GooeyBridge(distance: pillOffset)
                            .fill(Color(nsColor: .controlBackgroundColor))

                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: max(44, currentPillWidth), height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                            .padding(.leading, pillOffset)

                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44, height: 44)

                        ZStack(alignment: .leading) {
                            if expandProgress < 0.35 && tab.isNewTabState {
                                Text("Search google or websites.")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 42)
                                    .opacity(Double(1.0 - expandProgress / 0.35))
                            }

                            HStack(spacing: 8) {
                                TextField("Search google or websites.", text: $addressInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 15))
                                    .autocorrectionDisabled(true)
                                    .focused($isFocused)
                                    .onSubmit {
                                        if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
                                            navigateWithSuggestion(suggestions[selectedSuggestionIndex])
                                        } else {
                                            submitNavigation()
                                        }
                                    }
                                    .onExitCommand {
                                        dismissOrCollapseSearchBar()
                                    }

                                if !addressInput.isEmpty {
                                    Button(action: {
                                        addressInput = ""
                                        suggestions = []
                                        selectedSuggestionIndex = -1
                                        resetInactivityTimer()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 13))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .opacity(expandProgress >= 0.99 ? 1.0 : Double(max(0, min(1.0, (expandProgress - 0.2) / 0.8))))
                            .allowsHitTesting(expandProgress > 0.5 || !tab.isNewTabState)
                        }
                        .frame(width: max(44, currentPillWidth), height: 44, alignment: .leading)
                        .padding(.leading, pillOffset)
                    }
                    .frame(width: containerWidth, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if expandProgress < 0.5 && tab.isNewTabState {
                            expandSearchBar()
                        }
                    }
                    .onHover { hovering in
                        isIdleHovered = hovering
                        if hovering {
                            resetInactivityTimer()
                        }
                    }

                    if !suggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                                SuggestionRowView(
                                    item: item,
                                    isSelected: index == selectedSuggestionIndex
                                ) {
                                    navigateWithSuggestion(item)
                                }
                                if index < suggestions.count - 1 {
                                    Divider()
                                        .opacity(0.35)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(width: max(44, currentPillWidth))
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
                        .frame(width: containerWidth, alignment: .trailing)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: -4))
                                    .combined(with: .scale(scale: 0.99, anchor: .top)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.99, anchor: .top))
                            )
                        )
                        .animation(.spring(response: 0.18, dampingFraction: 0.86), value: suggestions.map { $0.id })
                    } else if tab.isNewTabState {
                        ShortcutsSectionView(
                            viewModel: viewModel,
                            tab: tab,
                            onAddShortcut: {
                                editingShortcut = nil
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                    isAddShortcutPresented = true
                                }
                            },
                            onEditShortcut: { item in
                                editingShortcut = item
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                    isAddShortcutPresented = true
                                }
                            }
                        )
                        .padding(.top, 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }

                    Spacer()
                }

                if isAddShortcutPresented {
                    Color.black.opacity(0.25)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                isAddShortcutPresented = false
                                editingShortcut = nil
                            }
                        }
                        .transition(.opacity)
                        .zIndex(99)

                    ShortcutEditorModalView(
                        editingItem: editingShortcut,
                        onSave: { title, url in
                            if let editing = editingShortcut {
                                ShortcutsManager.shared.updateShortcut(id: editing.id, title: title, url: url)
                            } else {
                                ShortcutsManager.shared.addShortcut(title: title, url: url)
                            }
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                isAddShortcutPresented = false
                                editingShortcut = nil
                            }
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                isAddShortcutPresented = false
                                editingShortcut = nil
                            }
                        },
                        onDelete: editingShortcut != nil ? {
                            if let editing = editingShortcut {
                                ShortcutsManager.shared.removeShortcut(id: editing.id)
                            }
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                isAddShortcutPresented = false
                                editingShortcut = nil
                            }
                        } : nil
                    )
                    .transition(.scale(scale: 0.95, anchor: .center).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            .onAppear {
                expandProgress = 1.0
                isExpanded = true
                syncInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
                resetInactivityTimer()
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if isAddShortcutPresented {
                        return event
                    }
                    if tab.isNewTabState || tab.isAddressOverlayPresented {
                        if event.keyCode == 53 {
                            dismissOrCollapseSearchBar()
                            return nil
                        }
                        if event.keyCode == 125 {
                            if !suggestions.isEmpty {
                                withAnimation(.easeInOut(duration: 0.08)) {
                                    selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
                                }
                                return nil
                            }
                        } else if event.keyCode == 126 {
                            if !suggestions.isEmpty {
                                withAnimation(.easeInOut(duration: 0.08)) {
                                    selectedSuggestionIndex = max(-1, selectedSuggestionIndex - 1)
                                }
                                return nil
                            }
                        }
                        if !isFocused {
                            if let chars = event.characters, !chars.isEmpty,
                               !event.modifierFlags.contains(.command),
                               !event.modifierFlags.contains(.control) {
                                if expandProgress < 0.5 {
                                    expandSearchBar()
                                } else {
                                    isFocused = true
                                }
                            }
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                inactivityTask?.cancel()
                inactivityTask = nil
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    eventMonitor = nil
                }
            }
            .onChange(of: addressInput) { _, newValue in
                let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    resetInactivityTimer()
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
                        suggestions = []
                        selectedSuggestionIndex = -1
                    }
                } else {
                    inactivityTask?.cancel()
                    let local = HistoryManager.shared.localSuggestions(for: text)
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
                        suggestions = local
                    }
                    HistoryManager.shared.fetchSuggestions(for: text) { remoteItems in
                        if addressInput.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
                                suggestions = remoteItems
                            }
                        }
                    }
                }
            }
            .onChange(of: tab.id) {
                expandProgress = 1.0
                isExpanded = true
                syncInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
                resetInactivityTimer()
            }
            .onChange(of: tab.isAddressOverlayPresented) { _, isPresented in
                if isPresented {
                    expandProgress = 1.0
                    isExpanded = true
                    syncInput()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                    resetInactivityTimer()
                } else {
                    inactivityTask?.cancel()
                }
            }
        }
    }

    private func expandSearchBar() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            expandProgress = 1.0
            isExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isFocused = true
        }
        resetInactivityTimer()
    }

    private func dismissOrCollapseSearchBar() {
        if !tab.isNewTabState {
            viewModel.dismissAddressBar()
        } else {
            inactivityTask?.cancel()
            inactivityTask = nil
            addressInput = ""
            suggestions = []
            selectedSuggestionIndex = -1
            isFocused = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                expandProgress = 0.0
                isExpanded = false
            }
        }
    }

    private func collapseSearchBar() {
        guard tab.isNewTabState && addressInput.isEmpty else { return }
        dismissOrCollapseSearchBar()
    }

    private func resetInactivityTimer() {
        inactivityTask?.cancel()
        guard tab.isNewTabState else { return }
        guard addressInput.isEmpty else { return }
        inactivityTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    if addressInput.isEmpty && tab.isNewTabState {
                        collapseSearchBar()
                    }
                }
            }
        }
    }

    private func syncInput() {
        addressInput = tab.addressText
        withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
            suggestions = []
            selectedSuggestionIndex = -1
        }
    }

    private func navigateWithSuggestion(_ item: SuggestionItem) {
        inactivityTask?.cancel()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
            suggestions = []
            selectedSuggestionIndex = -1
        }
        HistoryManager.shared.recordSearch(query: item.query)
        viewModel.navigate(tab: tab, to: item.fullURL)
    }

    private func submitNavigation() {
        let text = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inactivityTask?.cancel()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
            suggestions = []
            selectedSuggestionIndex = -1
        }
        if !viewModel.isDirectURL(text) {
            HistoryManager.shared.recordSearch(query: text)
        }
        viewModel.navigate(tab: tab, to: text)
    }
}

struct SuggestionRowView: View {
    let item: SuggestionItem
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: item.isRecentSearch ? "clock.arrow.circlepath" : "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(item.isRecentSearch ? .accentColor : .secondary)
                    .frame(width: 16)

                Text(item.query)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if item.isRecentSearch {
                    Text("Search history")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected || isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct AnimatedSpeakerIcon: View {
    let isMuted: Bool

    var body: some View {
        ZStack {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .semibold))
                .scaleEffect(isMuted ? 0.001 : 1.0)
                .opacity(isMuted ? 0.0 : 1.0)
                .rotationEffect(.degrees(isMuted ? -35 : 0))

            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 9, weight: .semibold))
                .scaleEffect(isMuted ? 1.0 : 0.001)
                .opacity(isMuted ? 1.0 : 0.0)
                .rotationEffect(.degrees(isMuted ? 0 : 35))
        }
        .frame(width: 16, height: 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isMuted)
    }
}

struct TabPillView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var viewModel: BrowserViewModel
    let isSelected: Bool
    let tabNamespace: Namespace.ID
    let tabWidth: CGFloat
    let isBeingDragged: Bool
    let isAnyTabDragging: Bool
    let onDragStarted: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onSelect: () -> Void

    @State private var isHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isSpeakerHovered: Bool = false

    private var showsTitle: Bool {
        tabWidth >= 76
    }

    private var showsSpeakerButton: Bool {
        guard !tab.isNewTabState else { return false }
        if tab.isPlayingMedia {
            if tabWidth >= 66 {
                return true
            } else if tabWidth >= 42 {
                return !showsCloseButton || !isHovered
            }
        } else if tab.isMuted && tab.hasPlayedMedia {
            if tabWidth >= 66 {
                return true
            } else if tabWidth >= 42 {
                return !showsCloseButton || !isHovered
            }
        }
        return false
    }

    private var showsCloseButton: Bool {
        if tabWidth >= 76 {
            return isHovered || isSelected
        } else if tabWidth >= 42 {
            return isHovered
        }
        return false
    }

    private var trailingPadding: CGFloat {
        if showsCloseButton && showsSpeakerButton {
            return 40
        } else if showsCloseButton || showsSpeakerButton {
            return 22
        }
        return 4
    }

    private var iconSize: CGFloat {
        if tabWidth >= 30 {
            return 15
        } else if tabWidth >= 20 {
            return 13
        } else if tabWidth >= 13 {
            return 10
        }
        return 0
    }

    private var pillCornerRadius: CGFloat {
        min(7, max(2, tabWidth / 2))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isSelected {
                if isAnyTabDragging {
                    RoundedRectangle(cornerRadius: pillCornerRadius)
                        .fill(Color.primary.opacity(isBeingDragged ? 0.14 : 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: pillCornerRadius)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: pillCornerRadius)
                        .fill(Color.primary.opacity(0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: pillCornerRadius)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "activeTabSlidingPill", in: tabNamespace)
                }
            } else if isHovered {
                RoundedRectangle(cornerRadius: pillCornerRadius)
                    .fill(Color.primary.opacity(0.04))
            }

            HStack(spacing: 5) {
                if iconSize > 0 {
                    if tab.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: iconSize, height: iconSize)
                    } else if let favicon = tab.favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: iconSize, height: iconSize)
                            .cornerRadius(1)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: iconSize * 0.8))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .frame(width: iconSize, height: iconSize)
                    }
                } else {
                    Capsule()
                        .fill(isSelected ? Color.primary.opacity(0.8) : Color.primary.opacity(isHovered ? 0.4 : 0.18))
                        .frame(width: max(2, min(tabWidth - 2, 4)), height: 14)
                }

                if showsTitle {
                    Text(displayTitle)
                        .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, showsTitle ? 8 : (showsCloseButton ? 4 : 2))
            .padding(.trailing, trailingPadding)
            .frame(width: tabWidth, height: 30, alignment: showsTitle ? .leading : .center)
            .clipped()
            .allowsHitTesting(false)

            TabPillInteractionView(
                tabWidth: tabWidth,
                showsCloseButton: showsCloseButton,
                showsSpeakerButton: showsSpeakerButton,
                onDragStarted: onDragStarted,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                onSelect: onSelect,
                onMiddleClick: {
                    PerformanceMonitor.shared.log(event: "Click", details: "Middle-click closed tab: \"\(displayTitle)\"")
                    viewModel.closeTab(id: tab.id)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsSpeakerButton || showsCloseButton {
                HStack(spacing: 3) {
                    Spacer()

                    if showsSpeakerButton {
                        Button(action: {
                            PerformanceMonitor.shared.log(event: "Click", details: "Tab speaker button clicked: \"\(displayTitle)\" (muted: \(tab.isMuted))")
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                                viewModel.toggleMute(tab: tab)
                            }
                        }) {
                            AnimatedSpeakerIcon(isMuted: tab.isMuted)
                                .foregroundColor(tab.isMuted ? Color.secondary.opacity(0.85) : (isSelected ? Color.primary : Color.primary.opacity(0.85)))
                                .background(
                                    Circle().fill(Color.primary.opacity(isSpeakerHovered ? 0.12 : 0))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(tab.isMuted ? "Unmute tab" : "Mute tab")
                        .onHover { hovering in
                            isSpeakerHovered = hovering
                        }
                    }

                    if showsCloseButton {
                        Button(action: {
                            PerformanceMonitor.shared.log(event: "Click", details: "Tab close button: \"\(displayTitle)\"")
                            viewModel.closeTab(id: tab.id)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle().fill(Color.primary.opacity(isCloseHovered ? 0.12 : 0))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isCloseHovered = hovering
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .frame(width: tabWidth, height: 30)
        .clipped()
        .shadow(color: Color.black.opacity(isBeingDragged ? 0.18 : 0), radius: isBeingDragged ? 5 : 0, x: 0, y: isBeingDragged ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: tabWidth)
        .help(displayTitle)
        .contextMenu {
            Button {
                viewModel.toggleMute(tab: tab)
            } label: {
                Label(tab.isMuted ? "Unmute Tab" : "Mute Tab", systemImage: tab.isMuted ? "speaker.wave.2" : "speaker.slash")
            }

            Divider()

            Button {
                viewModel.closeTab(id: tab.id)
            } label: {
                Label("Close Tab", systemImage: "xmark")
            }

            Button {
                viewModel.closeOtherTabs(id: tab.id)
            } label: {
                Label("Close Other Tabs", systemImage: "xmark.circle")
            }

            Button {
                viewModel.duplicateTab(id: tab.id)
            } label: {
                Label("Duplicate Tab", systemImage: "plus.square.on.square")
            }

            Button {
                tab.reload()
            } label: {
                Label("Reload Tab", systemImage: "arrow.clockwise")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }

    }

    private var displayTitle: String {
        if !tab.pageTitle.isEmpty {
            return tab.pageTitle
        }
        if let host = tab.currentURL?.host {
            return host
        }
        return "New Tab"
    }
}

struct NewTabButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))

            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .background(NonDraggableBackground())
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .help("New Tab (⌘T)")
    }
}

struct NavButton: View {
    let icon: String
    let tooltip: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && !disabled ? Color.primary.opacity(0.08) : Color.clear)
                    .frame(width: 26, height: 26)

                NavSvgIcon(name: icon)
                    .foregroundColor(disabled ? .secondary.opacity(0.35) : (isHovered ? .primary : .secondary))
                    .frame(width: 15, height: 15)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

struct NavSvgIcon: View {
    let name: String

    var body: some View {
        if let img = AssetLoader.image(named: name) {
            Image(nsImage: img)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackSymbol
        }
    }

    @ViewBuilder
    private var fallbackSymbol: some View {
        switch name {
        case "back":
            Image(systemName: "chevron.backward")
                .font(.system(size: 12, weight: .medium))
        case "forward":
            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .medium))
        case "reload":
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
        case "home":
            Image(systemName: "house")
                .font(.system(size: 12, weight: .medium))
        default:
            EmptyView()
        }
    }
}

enum AssetLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let candidates: [URL] = [
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Assets"),
            Bundle.main.url(forResource: name, withExtension: "svg"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Assets/\(name).svg"),
            Bundle.main.bundleURL.appendingPathComponent("Assets/\(name).svg"),
            currentDir.appendingPathComponent("Assets/\(name).svg"),
            sourceDir.appendingPathComponent("Assets/\(name).svg")
        ].compactMap { $0 }

        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                cache[name] = img
                return img
            }
        }
        return nil
    }
}

struct FindBarOverlay: View {
    @ObservedObject var tab: Tab

    var body: some View {
        ZStack {
            if tab.isFindPresented {
                FindBarView(findState: tab.findState)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: tab.isFindPresented)
    }
}


