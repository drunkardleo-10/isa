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

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .zIndex(10)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                ForEach(viewModel.tabs) { tab in
                    if !tab.isNewTabState || tab.webView != nil || tab.isSleeping {
                        WebView(tab: tab)
                            .opacity(tab.id == viewModel.selectedTabId && !tab.isNewTabState ? 1 : 0)
                            .allowsHitTesting(tab.id == viewModel.selectedTabId && !tab.isNewTabState && !tab.isAddressOverlayPresented)
                    }
                }

                ActiveTabOverlayView(tab: viewModel.activeTab, viewModel: viewModel)
            }
        }
        .onAppear {
            PerformanceMonitor.shared.log(event: "WindowReady", details: "Window content rendered on screen")
        }
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
                .frame(width: 78, height: 32)

            tabStripView

            Button(action: {
                PerformanceMonitor.shared.log(event: "Click", details: "Theme toggle button (Current: \(viewModel.theme.rawValue))")
                viewModel.toggleTheme()
            }) {
                Image(systemName: viewModel.theme.iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Appearance: \(viewModel.theme.rawValue.capitalized)")
        }
        .frame(height: 32)
        .padding(.trailing, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(NonDraggableBackground())
    }

    private var tabStripView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let tabCount = viewModel.tabs.count
            let spacing: CGFloat = tabCount > 60 ? 1 : (tabCount > 25 ? 1.5 : (tabCount > 12 ? 2 : 4))
            let plusButtonWidth: CGFloat = 22
            let maxTabWidth: CGFloat = 180
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
                        .frame(maxWidth: .infinity, maxHeight: 32)
                }
            }
            .frame(width: availableWidth, height: 32, alignment: .leading)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: 32)
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
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onSelect = onSelect
        view.onMiddleClick = onMiddleClick
    }

    final class PillNSView: NSView {
        var tabWidth: CGFloat = 100
        var showsCloseButton: Bool = false
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
            return NSSize(width: NSView.noIntrinsicMetric, height: 26)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let hit = super.hitTest(point) else { return nil }
            let localPoint = superview != nil ? convert(point, from: superview) : point
            if showsCloseButton && localPoint.x >= (bounds.width - 22) {
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
                                isFocused = true
                            }
                        }
                }

                VStack(spacing: 4) {
                    Spacer()
                        .frame(height: 140)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))

                        TextField("Enter a web address", text: $addressInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .focused($isFocused)
                            .onSubmit {
                                if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
                                    navigateWithSuggestion(suggestions[selectedSuggestionIndex])
                                } else {
                                    submitNavigation()
                                }
                            }
                            .onExitCommand {
                                if !tab.isNewTabState {
                                    viewModel.dismissAddressBar()
                                }
                            }

                        if !addressInput.isEmpty {
                            Button(action: {
                                addressInput = ""
                                suggestions = []
                                selectedSuggestionIndex = -1
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 480, height: 46)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)

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
                        .frame(width: 480)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: -4))
                                    .combined(with: .scale(scale: 0.99, anchor: .top)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.99, anchor: .top))
                            )
                        )
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
                .animation(.spring(response: 0.18, dampingFraction: 0.86), value: suggestions.map { $0.id })

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
                syncInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if isAddShortcutPresented {
                        return event
                    }
                    if tab.isNewTabState || tab.isAddressOverlayPresented {
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
                                isFocused = true
                            }
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    eventMonitor = nil
                }
            }
            .onChange(of: addressInput) { _, newValue in
                tab.addressText = newValue
                let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
                        suggestions = []
                        selectedSuggestionIndex = -1
                    }
                } else {
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
                syncInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            }
            .onChange(of: tab.isAddressOverlayPresented) { _, isPresented in
                if isPresented {
                    syncInput()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
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

    private var showsTitle: Bool {
        tabWidth >= 76
    }

    private var showsCloseButton: Bool {
        if tabWidth >= 76 {
            return isHovered || isSelected
        } else if tabWidth >= 42 {
            return isHovered
        }
        return false
    }

    private var iconSize: CGFloat {
        if tabWidth >= 30 {
            return 14
        } else if tabWidth >= 20 {
            return 12
        } else if tabWidth >= 13 {
            return 9
        }
        return 0
    }

    private var pillCornerRadius: CGFloat {
        min(6, max(2, tabWidth / 2))
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
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, showsTitle ? 8 : (showsCloseButton ? 4 : 2))
            .padding(.trailing, showsCloseButton ? 20 : 4)
            .frame(width: tabWidth, height: 26, alignment: showsTitle ? .leading : .center)
            .clipped()
            .allowsHitTesting(false)

            TabPillInteractionView(
                tabWidth: tabWidth,
                showsCloseButton: showsCloseButton,
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

            if showsCloseButton {
                HStack {
                    Spacer()
                    Button(action: {
                        PerformanceMonitor.shared.log(event: "Click", details: "Tab close button: \"\(displayTitle)\"")
                        viewModel.closeTab(id: tab.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                            .background(
                                Circle().fill(Color.primary.opacity(isCloseHovered ? 0.12 : 0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                }
            }
        }
        .frame(width: tabWidth, height: 26)
        .clipped()
        .shadow(color: Color.black.opacity(isBeingDragged ? 0.18 : 0), radius: isBeingDragged ? 5 : 0, x: 0, y: isBeingDragged ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: tabWidth)
        .help(displayTitle)
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
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))

            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .frame(width: 20, height: 20)
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

