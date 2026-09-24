import SwiftUI
import AppKit
import ObjectiveC

struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 10)
        .frame(height: 6)
        .transition(.opacity)
    }
}

struct MinimiseTabsIcon: View {
    let isMinimised: Bool

    var body: some View {
        Canvas { context, size in
            let strokeWidth: CGFloat = 1.35
            let cornerRadius: CGFloat = 3.2
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)

            let outerPath = Path(roundedRect: rect, cornerRadius: cornerRadius)
            context.stroke(outerPath, with: .color(.primary.opacity(0.85)), lineWidth: strokeWidth)

            let dividerX = rect.minX + rect.width * 0.36
            var dividerPath = Path()
            dividerPath.move(to: CGPoint(x: dividerX, y: rect.minY))
            dividerPath.addLine(to: CGPoint(x: dividerX, y: rect.maxY))
            context.stroke(dividerPath, with: .color(.primary.opacity(0.85)), lineWidth: strokeWidth)

            if !isMinimised {
                let dashX1 = rect.minX + 2.2
                let dashX2 = dividerX - 2.2
                let usableHeight = rect.height - 4.0
                let step = usableHeight / 3.0
                let dashStroke: CGFloat = 1.2

                for i in 0..<3 {
                    let y = rect.minY + 2.0 + step * CGFloat(i) + step * 0.5
                    var dashPath = Path()
                    dashPath.move(to: CGPoint(x: dashX1, y: y))
                    dashPath.addLine(to: CGPoint(x: dashX2, y: y))
                    context.stroke(dashPath, with: .color(.primary.opacity(0.85)), style: StrokeStyle(lineWidth: dashStroke, lineCap: .round))
                }
            }
        }
        .frame(width: 17, height: 13)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Namespace private var tabNamespace
    @State private var draggingTabId: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var dragInitialIndex: Int? = nil
    @State private var dragTargetIndex: Int? = nil
    @State private var sidebarDraggingTabId: UUID? = nil
    @State private var sidebarDragOffset: CGSize = .zero
    @State private var sidebarDragInitialIndex: Int? = nil
    @State private var sidebarDropTarget: SidebarDropTarget? = nil
    @State private var isDraggingPinnedTab: Bool = false
    @State private var isShieldPopoverPresented: Bool = false
    @State private var isDownloadsPopoverPresented: Bool = false
    @State private var keyMonitor: Any? = nil
    @State private var mouseMonitor: Any? = nil
    @State private var isZenBarHidden: Bool = false
    @State private var zenIdleTimer: Task<Void, Never>? = nil
    @State private var isHoveringTopBar: Bool = false
    @State private var isHoveringSidebar: Bool = false
    @State private var isHoveringMinimiseButton: Bool = false
    @State private var isHoveringNewTabCollapsed: Bool = false
    @State private var isHoveringTopTriggerZone: Bool = false
    @State private var isHoveringLeftTriggerZone: Bool = false
    @State private var hoveredSidebarTabId: UUID? = nil
    @ObservedObject private var downloadManager: DownloadManager = DownloadManager.shared

    private var isSidebarEffectivelyExpanded: Bool {
        return !viewModel.isSidebarCollapsed
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.tabPlacement == .top {
                VStack(spacing: 0) {
                    topBar
                        .onHover { hovering in
                            isHoveringTopBar = hovering
                            if hovering {
                                zenIdleTimer?.cancel()
                                zenIdleTimer = nil
                                if isZenBarHidden {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isZenBarHidden = false
                                    }
                                }
                            } else {
                                startZenTimer()
                            }
                        }
                        .frame(height: (viewModel.isZenModeEnabled && isZenBarHidden) ? 0 : 38)
                        .opacity((viewModel.isZenModeEnabled && isZenBarHidden) ? 0 : 1)
                        .offset(y: (viewModel.isZenModeEnabled && isZenBarHidden) ? -38 : 0)
                        .clipped()
                        .zIndex(10)

                    mainContentArea
                }
            } else {
                HStack(spacing: 0) {
                    leftTabSidebar
                        .onHover { hovering in
                            isHoveringSidebar = hovering
                            if hovering {
                                zenIdleTimer?.cancel()
                                zenIdleTimer = nil
                                if isZenBarHidden {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isZenBarHidden = false
                                    }
                                }
                            } else {
                                startZenTimer()
                            }
                        }
                        .frame(width: (viewModel.isZenModeEnabled && isZenBarHidden) ? 0 : (viewModel.isSidebarCollapsed ? 48 : 240))
                        .opacity((viewModel.isZenModeEnabled && isZenBarHidden) ? 0 : 1)
                        .offset(x: (viewModel.isZenModeEnabled && isZenBarHidden) ? -(viewModel.isSidebarCollapsed ? 48 : 240) : 0)
                        .clipped()
                        .zIndex(10)
                        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: viewModel.isSidebarCollapsed)

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: (viewModel.isZenModeEnabled && isZenBarHidden) ? 0 : 1)
                        .opacity((viewModel.isZenModeEnabled && isZenBarHidden) ? 0 : 1)

                    mainContentArea
                }
            }

            if viewModel.isZenModeEnabled && isZenBarHidden {
                if viewModel.tabPlacement == .top {
                    Color.clear
                        .frame(height: 16)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringTopTriggerZone = hovering
                            if hovering {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isZenBarHidden = false
                                }
                            } else {
                                startZenTimer()
                            }
                        }
                        .zIndex(100)
                } else {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 16)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                isHoveringLeftTriggerZone = hovering
                                if hovering {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        isZenBarHidden = false
                                    }
                                } else {
                                    startZenTimer()
                                }
                            }
                            .zIndex(100)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .overlay(alignment: viewModel.tabPlacement == .top ? .topTrailing : .topLeading) {
            Color.clear

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
                    .padding(.top, viewModel.tabPlacement == .top ? 42 : 72)
                    .padding(.leading, viewModel.tabPlacement == .top ? 0 : 20)
                    .padding(.trailing, viewModel.tabPlacement == .top ? 12 : 0)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: viewModel.tabPlacement == .top ? .topTrailing : .topLeading).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: viewModel.tabPlacement == .top ? .topTrailing : .topLeading).combined(with: .opacity)
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
                    .padding(.top, viewModel.tabPlacement == .top ? 42 : 120)
                    .padding(.leading, viewModel.tabPlacement == .top ? 0 : 20)
                    .padding(.trailing, viewModel.tabPlacement == .top ? 12 : 0)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: viewModel.tabPlacement == .top ? .topTrailing : .topLeading).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: viewModel.tabPlacement == .top ? .topTrailing : .topLeading).combined(with: .opacity)
                    ))
                    .zIndex(100)
            }

            if viewModel.isHistoryViewPresented {
                HistoryView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(150)
            }
        }
        .onExitCommand {
            if viewModel.isHistoryViewPresented {
                viewModel.dismissHistoryView()
            } else if viewModel.activeTab.isFindPresented {
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
                    let isY = (chars == "y") || event.keyCode == 16

                    if event.keyCode == 53 {
                        if viewModel.isHistoryViewPresented {
                            viewModel.dismissHistoryView()
                            return nil
                        }
                    }

                    if isCmd && isY {
                        viewModel.toggleHistoryView()
                        return nil
                    }

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
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { event in
                    guard viewModel.isZenModeEnabled else { return event }
                    guard let window = event.window ?? NSApp.keyWindow else { return event }
                    let location = event.locationInWindow
                    let windowHeight = window.frame.height

                    if viewModel.tabPlacement == .top {
                        if location.y >= windowHeight - 20 {
                            if isZenBarHidden {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isZenBarHidden = false
                                }
                            }
                        } else if !isHoveringTopBar {
                            startZenTimer()
                        }
                    } else {
                        if location.x <= 20 {
                            if isZenBarHidden {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isZenBarHidden = false
                                }
                            }
                        } else if !isHoveringSidebar {
                            startZenTimer()
                        }
                    }
                    return event
                }
            }
            startZenTimer()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
            zenIdleTimer?.cancel()
            zenIdleTimer = nil
        }
        .onChange(of: viewModel.isZenModeEnabled) { enabled in
            if !enabled {
                zenIdleTimer?.cancel()
                zenIdleTimer = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isZenBarHidden = false
                }
            } else {
                startZenTimer()
            }
        }
        .onChange(of: viewModel.tabPlacement) { _ in
            zenIdleTimer?.cancel()
            zenIdleTimer = nil
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isZenBarHidden = false
            }
            startZenTimer()
        }
        .onChange(of: viewModel.selectedTabId) { _ in
            zenIdleTimer?.cancel()
            zenIdleTimer = nil
            if !viewModel.isZenModeEnabled {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isZenBarHidden = false
                }
            }
            startZenTimer()
        }
        .onChange(of: viewModel.activeTab.isAddressOverlayPresented) { presented in
            if presented {
                zenIdleTimer?.cancel()
                zenIdleTimer = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isZenBarHidden = false
                }
            } else {
                startZenTimer()
            }
        }
        .onReceive(downloadManager.objectWillChange) { _ in }
        .onReceive(viewModel.activeTab.objectWillChange) { _ in }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor(theme: viewModel.theme))
        .background(keyboardShortcutsBackground)
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

            Button(action: {
                PerformanceMonitor.shared.log(event: "Click", details: "History view toggle")
                viewModel.toggleHistoryView()
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.isHistoryViewPresented ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Browsing History (⌘Y)")

            AnimatedThemeToggle(viewModel: viewModel)

            Button(action: {
                PerformanceMonitor.shared.log(event: "Click", details: "Settings top bar icon")
                viewModel.openSettings()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.activeTab.currentURL?.absoluteString == "isa://settings" ? .primary : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (isa://settings)")
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
            NavButton(icon: "reload", tooltip: "Reload (⌘R)", disabled: viewModel.activeTab.isNewTabState || viewModel.activeTab.isInternal) {
                viewModel.reloadActiveTab()
            }
            NavButton(icon: "home", tooltip: "Home", disabled: viewModel.activeTab.isNewTabState || viewModel.activeTab.isInternal) {
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
                        .background(alignment: .leading) {
                            if let selectedIndex = viewModel.tabs.firstIndex(where: { $0.id == viewModel.selectedTabId }),
                               draggingTabId == nil {
                                let pillRadius = min(7, max(2, tabWidth / 2))
                                RoundedRectangle(cornerRadius: pillRadius)
                                    .fill(Color.primary.opacity(0.09))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: pillRadius)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                    )
                                    .frame(width: tabWidth, height: 30)
                                    .offset(x: CGFloat(selectedIndex) * (tabWidth + spacing))
                            }
                        }
                        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: viewModel.selectedTabId)
                        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: viewModel.tabs.count)
                    }
                    .clipped()
                    .background(NonDraggableBackground())
                    .frame(width: isOverflowing ? availableWidth : min(totalContentWidth, availableWidth), alignment: .leading)
                    .onChange(of: viewModel.selectedTabId) { _, newId in
                        if isOverflowing && draggingTabId == nil {
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

    private var mainContentArea: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .windowBackgroundColor)

            ForEach(viewModel.tabs) { tab in
                if tab.isInternal {
                    SettingsView(viewModel: viewModel)
                        .opacity(tab.id == viewModel.selectedTabId ? 1 : 0)
                        .allowsHitTesting(tab.id == viewModel.selectedTabId && !tab.isAddressOverlayPresented && !isShieldPopoverPresented && !isDownloadsPopoverPresented && !viewModel.isHistoryViewPresented)
                } else if !tab.isNewTabState || tab.webView != nil || tab.isSleeping {
                    ZStack {
                        WebView(tab: tab)
                        if let error = tab.pageError {
                            PageCrashErrorView(error: error) {
                                tab.reload()
                            }
                        }
                    }
                    .opacity(tab.id == viewModel.selectedTabId && !tab.isNewTabState ? 1 : 0)
                    .allowsHitTesting(tab.id == viewModel.selectedTabId && !tab.isNewTabState && !tab.isAddressOverlayPresented && !isShieldPopoverPresented && !isDownloadsPopoverPresented && !viewModel.isHistoryViewPresented)
                }
            }

            ActiveTabOverlayView(tab: viewModel.activeTab, viewModel: viewModel)

            FindBarOverlay(tab: viewModel.activeTab)
        }
    }

    private var leftTabSidebar: some View {
        ZStack(alignment: .leading) {
            if isSidebarEffectivelyExpanded {
                expandedSidebarView
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity
                    ))
            } else {
                collapsedSidebarView
                    .transition(.opacity)
            }
        }
        .frame(width: isSidebarEffectivelyExpanded ? 240 : 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(NonDraggableBackground())
        .clipped()
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isSidebarEffectivelyExpanded)
    }

    private var collapsedSidebarView: some View {
        VStack(spacing: 0) {
            WindowDragHandle()
                .frame(width: 48, height: 28)

            Button(action: {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    viewModel.isSidebarCollapsed = false
                }
            }) {
                MinimiseTabsIcon(isMinimised: true)
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHoveringMinimiseButton ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Expand tabs")
            .onHover { isHoveringMinimiseButton = $0 }
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(viewModel.pinnedTabs) { tab in
                        collapsedTabIconRow(for: tab)
                    }
                    if !viewModel.pinnedTabs.isEmpty && !viewModel.unpinnedTabs.isEmpty {
                        Divider()
                            .opacity(0.12)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                    }
                    ForEach(viewModel.unpinnedTabs) { tab in
                        collapsedTabIconRow(for: tab)
                    }

                    Divider()
                        .opacity(0.12)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewModel.createNewTab()
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 34, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isHoveringNewTabCollapsed ? Color.primary.opacity(0.06) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New tab (⌘T)")
                    .onHover { isHoveringNewTabCollapsed = $0 }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .animation(.spring(response: 0.26, dampingFraction: 0.82), value: viewModel.selectedTabId)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: viewModel.tabs.map { $0.id })
            }

            Spacer(minLength: 6)

            Button(action: {
                viewModel.openSettings()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (isa://settings)")
            .padding(.bottom, 6)
        }
    }

    private func collapsedTabIconRow(for tab: Tab) -> some View {
        let isSelected = tab.id == viewModel.selectedTabId
        let isHovered = hoveredSidebarTabId == tab.id

        return ZStack {
            ZStack(alignment: .topTrailing) {
                tabFaviconView(for: tab)
                    .frame(width: 17, height: 17)

                if tab.isPlayingAudio {
                    Circle()
                        .fill(tab.isMuted ? Color.orange : Color.accentColor)
                        .frame(width: 5, height: 5)
                        .offset(x: 4, y: -4)
                } else if tab.isPinned {
                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 4, height: 4)
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: 34, height: 32)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.14))
                            .matchedGeometryEffect(id: "activeSidebarCollapsedTabSlidingPill", in: tabNamespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                }
            )
            .contentShape(Rectangle())
            .allowsHitTesting(false)

            SidebarTabInteractionView(
                showsCloseButton: false,
                showsSpeakerButton: false,
                enableDrag: false,
                onSelect: {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        viewModel.selectTab(id: tab.id)
                    }
                },
                onMiddleClick: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        PerformanceMonitor.shared.log(event: "Click", details: "Middle-click closed collapsed tab")
                        viewModel.closeTab(id: tab.id)
                    }
                }
            )
            .frame(width: 34, height: 32)
        }
        .frame(width: 34, height: 32)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .scale(scale: 0.85).combined(with: .opacity)
        ))
        .help(tabDisplayTitle(for: tab))
        .contextMenu {
            if tab.isPinned {
                Button("Unpin from Essentials") {
                    viewModel.togglePinTab(id: tab.id)
                }
                Divider()
            } else if tab.isPinnable && viewModel.pinnedTabs.count < 8 {
                Button("Pin to Essentials") {
                    viewModel.togglePinTab(id: tab.id)
                }
                Divider()
            }
            Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") {
                tab.toggleMute()
            }
            Button("Reload") {
                tab.reload()
            }
            Divider()
            Button("Close Tab") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.closeTab(id: tab.id)
                }
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredSidebarTabId = tab.id
            } else if hoveredSidebarTabId == tab.id {
                hoveredSidebarTabId = nil
            }
        }
    }

    private var expandedSidebarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                WindowDragHandle()
                    .frame(maxWidth: .infinity, maxHeight: 28)

                HStack(spacing: 4) {
                    Button(action: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            viewModel.isSidebarCollapsed = true
                        }
                    }) {
                        MinimiseTabsIcon(isMinimised: false)
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isHoveringMinimiseButton ? Color.primary.opacity(0.08) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Minimise tabs")
                    .onHover { isHoveringMinimiseButton = $0 }

                    Button(action: {
                        viewModel.goBackActiveTab()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(viewModel.activeTab.canGoBack ? .primary : .secondary.opacity(0.4))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.activeTab.canGoBack)
                    .help("Back (⌘[)")

                    Button(action: {
                        viewModel.goForwardActiveTab()
                    }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(viewModel.activeTab.canGoForward ? .primary : .secondary.opacity(0.4))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.activeTab.canGoForward)
                    .help("Forward (⌘])")

                    Button(action: {
                        viewModel.reloadActiveTab()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor((viewModel.activeTab.isNewTabState || viewModel.activeTab.isInternal) ? .secondary.opacity(0.4) : .primary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.activeTab.isNewTabState || viewModel.activeTab.isInternal)
                    .help("Reload (⌘R)")
                }
                .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                .opacity(isSidebarEffectivelyExpanded ? 1 : 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)



            topPinnedSectionView
                .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                .opacity(isSidebarEffectivelyExpanded ? 1 : 0)

            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.primary.opacity(0.09))
                    .frame(height: 1)

                Button(action: {
                    viewModel.clearUnpinnedTabs()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.75))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close all open unpinned tabs")
            }
            .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
            .opacity(isSidebarEffectivelyExpanded ? 1 : 0)
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 6)

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.createNewTab()
                }
            }) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("New tab")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                        .opacity(isSidebarEffectivelyExpanded ? 1 : 0)

                    Spacer()

                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 11, weight: .medium))
                        Text("T")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                    .opacity(isSidebarEffectivelyExpanded ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(Array(viewModel.unpinnedTabs.enumerated()), id: \.element.id) { index, tab in
                        if sidebarDropTarget == .unpinned(index: index) {
                            DropIndicatorLine()
                        }
                        sidebarTabRow(for: tab, index: index)
                    }
                    if sidebarDropTarget == .unpinned(index: viewModel.unpinnedTabs.count) {
                        DropIndicatorLine()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .animation(.spring(response: 0.26, dampingFraction: 0.82), value: viewModel.selectedTabId)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: viewModel.unpinnedTabs.map { $0.id })
            }

            Spacer(minLength: 6)

            Divider()
                .opacity(0.10)

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.openSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (isa://settings)")
                .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                .opacity(isSidebarEffectivelyExpanded ? 1 : 0)

                Spacer()

                AnimatedThemeToggle(viewModel: viewModel)
                    .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                    .opacity(isSidebarEffectivelyExpanded ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
    private enum PinnedGridItem: Identifiable {
        case tab(Tab)
        case preview(Tab)

        var id: String {
            switch self {
            case .tab(let tab): return tab.id.uuidString
            case .preview(let tab): return "preview_\(tab.id.uuidString)"
            }
        }
    }

    private var topPinnedSectionView: some View {
        Group {
            if viewModel.pinnedTabs.isEmpty && !isHoveringPinnedDrop {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.85))
                            Text("Add to Essentials")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        Text("Keep your favorite tabs just a\nclick away")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(2)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: 34, height: 34)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            } else {
                let pinned = viewModel.pinnedTabs
                let isIncoming = isHoveringPinnedDrop && !isDraggingPinnedTab
                let targetDropIdx: Int = {
                    if case .pinned(let idx) = sidebarDropTarget {
                        return min(pinned.count, max(0, idx))
                    }
                    return pinned.count
                }()
                let effectiveCount = pinned.count + (isIncoming ? 1 : 0)
                let cols = min(max(effectiveCount, 1), 4)
                let spacing: CGFloat = 8.0
                let tileHeight: CGFloat = 44.0
                let tileWidth = (216.0 - CGFloat(cols - 1) * spacing) / CGFloat(cols)
                let pitchX = tileWidth + spacing
                let pitchY = tileHeight + spacing

                let gridItems: [PinnedGridItem] = {
                    var items: [PinnedGridItem] = pinned.map { .tab($0) }
                    if isIncoming, let draggingId = sidebarDraggingTabId,
                       let draggedTab = viewModel.tabs.first(where: { $0.id == draggingId }) {
                        let insertIdx = min(items.count, max(0, targetDropIdx))
                        items.insert(.preview(draggedTab), at: insertIdx)
                    }
                    return items
                }()

                let rows = stride(from: 0, to: gridItems.count, by: cols).map {
                    Array(gridItems[$0..<min($0 + cols, gridItems.count)])
                }

                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<rows.count, id: \.self) { rowIdx in
                        HStack(spacing: spacing) {
                            ForEach(rows[rowIdx]) { item in
                                switch item {
                                case .tab(let tab):
                                    let originalIndex = pinned.firstIndex(where: { $0.id == tab.id }) ?? 0
                                    pinnedDynamicTileView(
                                        for: tab,
                                        index: originalIndex,
                                        cols: cols,
                                        tileWidth: tileWidth,
                                        tileHeight: tileHeight,
                                        pitchX: pitchX,
                                        pitchY: pitchY
                                    )
                                case .preview(let tab):
                                    pinnedDropPreviewTile(
                                        for: tab,
                                        width: tileWidth,
                                        height: tileHeight
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                                        removal: .scale(scale: 0.82).combined(with: .opacity)
                                    ))
                                }
                            }
                        }
                    }
                }
                .frame(width: 216, alignment: .topLeading)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pinned.map { $0.id })
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isIncoming)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: targetDropIdx)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: cols)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tileWidth)
                .animation(.spring(response: 0.26, dampingFraction: 0.82), value: viewModel.selectedTabId)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isHoveringPinnedDrop)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var isHoveringPinnedDrop: Bool {
        if case .pinned = sidebarDropTarget, !isDraggingPinnedTab {
            return true
        }
        return false
    }

    private func pinnedDropPreviewTile(for tab: Tab, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            tabFaviconView(for: tab)
                .frame(width: 22, height: 22)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
        )
        .shadow(color: Color.accentColor.opacity(0.25), radius: 8, x: 0, y: 3)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: width)
    }

    private func pinnedDynamicTileView(
        for tab: Tab,
        index: Int,
        cols: Int,
        tileWidth: CGFloat,
        tileHeight: CGFloat,
        pitchX: CGFloat,
        pitchY: CGFloat
    ) -> some View {
        let isSelected = tab.id == viewModel.selectedTabId
        let isHovered = hoveredSidebarTabId == tab.id
        let isBeingDragged = sidebarDraggingTabId == tab.id

        let initialIdx = sidebarDragInitialIndex ?? index
        let initialCol = initialIdx % cols
        let initialRow = initialIdx / cols
        let initialSlotX = CGFloat(initialCol) * pitchX
        let initialSlotY = CGFloat(initialRow) * pitchY

        let currentCol = index % cols
        let currentRow = index / cols
        let currentSlotX = CGFloat(currentCol) * pitchX
        let currentSlotY = CGFloat(currentRow) * pitchY

        let dragDeltaX = isBeingDragged ? (initialSlotX + sidebarDragOffset.width - currentSlotX) : 0
        let dragDeltaY = isBeingDragged ? (initialSlotY + sidebarDragOffset.height - currentSlotY) : 0

        return ZStack {
            ZStack(alignment: .topTrailing) {
                tabFaviconView(for: tab)
                    .frame(width: 22, height: 22)

                if tab.isPlayingAudio {
                    Circle()
                        .fill(tab.isMuted ? Color.orange : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: tileWidth, height: tileHeight)
            .background(
                ZStack {
                    if isSelected {
                        if sidebarDraggingTabId != nil {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        } else {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                                .matchedGeometryEffect(id: "activeSidebarPinnedTabSlidingPill", in: tabNamespace)
                        }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.11))
                    } else {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.065))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isBeingDragged
                            ? Color.white.opacity(0.35)
                            : (isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.04)),
                        lineWidth: 1
                    )
            )
            .allowsHitTesting(false)

            SidebarTabInteractionView(
                showsCloseButton: false,
                showsSpeakerButton: tab.isPlayingAudio,
                onDragStarted: {
                    handleSidebarTabDragStarted(tab: tab, isPinned: true, index: index)
                },
                onDragChanged: { deltaX, deltaY in
                    handleSidebarTabDragChanged(tab: tab, deltaX: deltaX, deltaY: deltaY, isPinned: true, index: index)
                },
                onDragEnded: {
                    handleSidebarTabDragEnded(tab: tab, isPinned: true, index: index)
                },
                onSelect: {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        viewModel.selectTab(id: tab.id)
                    }
                },
                onMiddleClick: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        PerformanceMonitor.shared.log(event: "Click", details: "Middle-click closed pinned tab")
                        viewModel.closeTab(id: tab.id)
                    }
                }
            )
            .frame(width: tileWidth, height: tileHeight)
        }
        .frame(width: tileWidth, height: tileHeight)
        .offset(x: dragDeltaX, y: dragDeltaY)
        .scaleEffect(isBeingDragged ? 1.05 : 1.0)
        .zIndex(isBeingDragged ? 100 : 1)
        .shadow(
            color: Color.black.opacity(isBeingDragged ? 0.38 : 0.0),
            radius: isBeingDragged ? 12 : 0,
            x: 0,
            y: isBeingDragged ? 6 : 0
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isBeingDragged)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tileWidth)
        .help(tabDisplayTitle(for: tab))
        .contextMenu {
            Button("Unpin from Top") {
                viewModel.unpinTab(id: tab.id)
            }
            Divider()
            Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") {
                tab.toggleMute()
            }
            Button("Reload") {
                tab.reload()
            }
            Divider()
            Button("Close Tab") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.closeTab(id: tab.id)
                }
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredSidebarTabId = tab.id
            } else if hoveredSidebarTabId == tab.id {
                hoveredSidebarTabId = nil
            }
        }
    }

    private func sidebarTabRow(for tab: Tab, index: Int) -> some View {
        let isSelected = tab.id == viewModel.selectedTabId
        let isHovered = hoveredSidebarTabId == tab.id
        let isBeingDragged = sidebarDraggingTabId == tab.id

        return ZStack {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 22, height: 22)
                    tabFaviconView(for: tab)
                        .frame(width: 15, height: 15)
                }

                Text(tabDisplayTitle(for: tab))
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .offset(x: isSidebarEffectivelyExpanded ? 0 : -20)
                    .opacity(isSidebarEffectivelyExpanded ? 1 : 0)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                ZStack {
                    if isSelected {
                        if sidebarDraggingTabId != nil {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.13))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.13))
                                .matchedGeometryEffect(id: "activeSidebarTabSlidingPill", in: tabNamespace)
                        }
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                    }
                }
            )
            .allowsHitTesting(false)

            SidebarTabInteractionView(
                showsCloseButton: isSidebarEffectivelyExpanded && (isHovered || isSelected),
                showsSpeakerButton: tab.isPlayingAudio,
                onDragStarted: {
                    handleSidebarTabDragStarted(tab: tab, isPinned: false, index: index)
                },
                onDragChanged: { deltaX, deltaY in
                    handleSidebarTabDragChanged(tab: tab, deltaX: deltaX, deltaY: deltaY, isPinned: false, index: index)
                },
                onDragEnded: {
                    handleSidebarTabDragEnded(tab: tab, isPinned: false, index: index)
                },
                onSelect: {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        viewModel.selectTab(id: tab.id)
                    }
                },
                onMiddleClick: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        PerformanceMonitor.shared.log(event: "Click", details: "Middle-click closed tab: \"\(tabDisplayTitle(for: tab))\"")
                        viewModel.closeTab(id: tab.id)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 4) {
                Spacer()

                if tab.isPlayingAudio {
                    AnimatedSpeakerIcon(isMuted: tab.isMuted)
                        .onTapGesture {
                            tab.toggleMute()
                        }
                }

                if isHovered || isSelected || viewModel.tabs.count > 1 {
                    Button(action: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            viewModel.closeTab(id: tab.id)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.85))
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity((isHovered || isSelected) ? 1 : 0)
                }
            }
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .offset(isBeingDragged ? sidebarDragOffset : .zero)
        .scaleEffect(isBeingDragged ? 1.02 : 1.0)
        .zIndex(isBeingDragged ? 50 : 1)
        .shadow(color: isBeingDragged ? Color.black.opacity(0.35) : Color.clear, radius: 10, x: 0, y: 5)
        .opacity(isBeingDragged ? (isHoveringPinnedDrop ? 0.0 : 0.85) : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isHoveringPinnedDrop)
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                viewModel.selectTab(id: tab.id)
            }
        })
        .transition(.asymmetric(
            insertion: .scale(scale: 0.88).combined(with: .opacity).combined(with: .move(edge: .top)),
            removal: .scale(scale: 0.85).combined(with: .opacity)
        ))
        .contextMenu {
            if tab.isPinnable && viewModel.pinnedTabs.count < 8 {
                Button("Pin to Top") {
                    viewModel.pinTab(id: tab.id)
                }
                Divider()
            }
            Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") {
                tab.toggleMute()
            }
            Button("Reload") {
                tab.reload()
            }
            Button("Duplicate Tab") {
                viewModel.duplicateTab(id: tab.id)
            }
            Divider()
            Button("Close Tab") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.closeTab(id: tab.id)
                }
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredSidebarTabId = tab.id
            } else if hoveredSidebarTabId == tab.id {
                hoveredSidebarTabId = nil
            }
        }
    }

    private func handleSidebarTabDragStarted(tab: Tab, isPinned: Bool, index: Int) {
        isDraggingPinnedTab = isPinned
        sidebarDraggingTabId = tab.id
        sidebarDragOffset = .zero
        sidebarDragInitialIndex = index
        sidebarDropTarget = nil
    }

    private func handleSidebarTabDragChanged(tab: Tab, deltaX: CGFloat, deltaY: CGFloat, isPinned: Bool, index: Int) {
        guard sidebarDraggingTabId == tab.id else { return }
        sidebarDragOffset = CGSize(width: deltaX, height: deltaY)

        if isPinned {
            let pinned = viewModel.pinnedTabs
            guard !pinned.isEmpty else { return }
            let cols = min(max(pinned.count, 1), 4)
            let spacing: CGFloat = 8.0
            let tileHeight: CGFloat = 44.0
            let tileWidth = (216.0 - CGFloat(cols - 1) * spacing) / CGFloat(cols)
            let pitchX = tileWidth + spacing
            let pitchY = tileHeight + spacing
            let initialIdx = sidebarDragInitialIndex ?? index
            let initialCol = initialIdx % cols
            let initialRow = initialIdx / cols
            let totalRows = max(1, (pinned.count + cols - 1) / cols)

            let exitPinnedThreshold = CGFloat(totalRows - initialRow) * pitchY + 16.0
            if deltaY > exitPinnedThreshold {
                let unpinnedShift = Int(round((deltaY - exitPinnedThreshold) / 38.0))
                let targetIdx = max(0, min(viewModel.unpinnedTabs.count, unpinnedShift))
                sidebarDropTarget = .unpinned(index: targetIdx)
            } else {
                sidebarDropTarget = nil
                let currentX = CGFloat(initialCol) * pitchX + deltaX
                let currentY = CGFloat(initialRow) * pitchY + deltaY
                let targetCol = max(0, min(cols - 1, Int(round(currentX / pitchX))))
                let targetRow = max(0, min(totalRows - 1, Int(round(currentY / pitchY))))
                let targetIdx = max(0, min(pinned.count - 1, targetRow * cols + targetCol))

                if let currentIdx = pinned.firstIndex(where: { $0.id == tab.id }), targetIdx != currentIdx {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    viewModel.movePinnedTab(from: currentIdx, to: targetIdx)
                }
            }
        } else {
            let pinnedThreshold = -(CGFloat(index) * 38.0 + 55.0)
            if deltaY <= pinnedThreshold && tab.isPinnable && viewModel.pinnedTabs.count < 8 {
                let pinned = viewModel.pinnedTabs
                let effectiveCount = pinned.count + 1
                let effectiveCols = min(max(effectiveCount, 1), 4)
                let spacing: CGFloat = 8.0
                let tileWidth = (216.0 - CGFloat(effectiveCols - 1) * spacing) / CGFloat(effectiveCols)
                let pitchX = tileWidth + spacing
                let pitchY: CGFloat = 44.0 + spacing
                let totalRows = max(1, (effectiveCount + effectiveCols - 1) / effectiveCols)
                let excessUp = max(0, pinnedThreshold - deltaY)
                let rowFromBottom = Int(excessUp / pitchY)
                let targetRow = max(0, min(totalRows - 1, totalRows - 1 - rowFromBottom))
                let rawCol = Int(round((deltaX + 108.0) / pitchX))
                let targetCol = max(0, min(effectiveCols - 1, rawCol))
                let targetIdx = max(0, min(pinned.count, targetRow * effectiveCols + targetCol))
                if sidebarDropTarget != .pinned(index: targetIdx) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        sidebarDropTarget = .pinned(index: targetIdx)
                    }
                }
            } else {
                let shift = Int(round(deltaY / 38.0))
                let targetIdx = max(0, min(viewModel.unpinnedTabs.count, index + shift + (shift > 0 ? 1 : 0)))
                if sidebarDropTarget != .unpinned(index: targetIdx) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        sidebarDropTarget = .unpinned(index: targetIdx)
                    }
                }
            }
        }
    }

    private func handleSidebarTabDragEnded(tab: Tab, isPinned: Bool, index: Int) {
        guard let draggedId = sidebarDraggingTabId else { return }

        if isPinned {
            if case .unpinned(let targetIdx) = sidebarDropTarget {
                viewModel.unpinTab(id: draggedId, atIndex: targetIdx)
            }
        } else {
            if case .pinned(let targetIdx) = sidebarDropTarget, tab.isPinnable, viewModel.pinnedTabs.count < 8 {
                viewModel.pinTab(id: draggedId, atIndex: targetIdx)
            } else if case .unpinned(let targetIdx) = sidebarDropTarget {
                let dst = (targetIdx > index) ? (targetIdx - 1) : targetIdx
                if dst != index {
                    viewModel.moveUnpinnedTab(from: index, to: dst)
                }
            }
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            sidebarDraggingTabId = nil
            sidebarDragOffset = .zero
            sidebarDragInitialIndex = nil
            sidebarDropTarget = nil
            isDraggingPinnedTab = false
        }
    }

    @ViewBuilder
    private func tabFaviconView(for tab: Tab) -> some View {
        if tab.isInternal {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .cornerRadius(2.5)
        } else {
            let host = (tab.currentURL?.host ?? "").lowercased()
            if host.contains("discord") {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.40, blue: 0.95))
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            } else if host.contains("reddit") {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.27, blue: 0.0))
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
            } else if host.contains("github") {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.primary)
            } else if host.contains("google") {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
            } else if host.contains("youtube") {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            } else if host.contains("ycombinator") {
                Image(systemName: "y.square.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
            } else if host.contains("wikipedia") {
                Image(systemName: "w.square.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else if host.contains("x.com") || host.contains("twitter") {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func tabDisplayTitle(for tab: Tab) -> String {
        if !tab.pageTitle.isEmpty {
            return tab.pageTitle
        }
        if tab.isInternal {
            return "Settings"
        }
        if let host = tab.currentURL?.host {
            return host
        }
        return "New Tab"
    }

    private func startZenTimer() {
        guard viewModel.isZenModeEnabled, !isZenBarHidden else { return }
        zenIdleTimer?.cancel()
        zenIdleTimer = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                zenIdleTimer = nil
                if shouldHideZenBar {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        isZenBarHidden = true
                    }
                }
            }
        }
    }

    private var shouldHideZenBar: Bool {
        viewModel.isZenModeEnabled &&
        !isHoveringTopBar &&
        !isHoveringSidebar &&
        !isHoveringTopTriggerZone &&
        !isHoveringLeftTriggerZone &&
        !isShieldPopoverPresented &&
        !isDownloadsPopoverPresented &&
        !viewModel.isHistoryViewPresented
    }

    private var keyboardShortcutsBackground: some View {
        Group {
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(1)
                }
            }.keyboardShortcut("1", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(2)
                }
            }.keyboardShortcut("2", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(3)
                }
            }.keyboardShortcut("3", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(4)
                }
            }.keyboardShortcut("4", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(5)
                }
            }.keyboardShortcut("5", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(6)
                }
            }.keyboardShortcut("6", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(7)
                }
            }.keyboardShortcut("7", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(8)
                }
            }.keyboardShortcut("8", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    viewModel.selectTabNumber(9)
                }
            }.keyboardShortcut("9", modifiers: .command)
            Button("") { viewModel.closeActiveTab() }.keyboardShortcut("w", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
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

struct SidebarTabInteractionView: NSViewRepresentable {
    var showsCloseButton: Bool = false
    var showsSpeakerButton: Bool = false
    var enableDrag: Bool = true
    var onDragStarted: (() -> Void)? = nil
    var onDragChanged: ((CGFloat, CGFloat) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    var onMiddleClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> SidebarTabNSView {
        let view = SidebarTabNSView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: SidebarTabNSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ view: SidebarTabNSView) {
        view.showsCloseButton = showsCloseButton
        view.showsSpeakerButton = showsSpeakerButton
        view.enableDrag = enableDrag
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onSelect = onSelect
        view.onMiddleClick = onMiddleClick
    }

    final class SidebarTabNSView: NSView {
        var showsCloseButton: Bool = false
        var showsSpeakerButton: Bool = false
        var enableDrag: Bool = true
        var onDragStarted: (() -> Void)?
        var onDragChanged: ((CGFloat, CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?
        var onSelect: (() -> Void)?
        var onMiddleClick: (() -> Void)?

        private var startLocation: NSPoint = .zero
        private var isDragging: Bool = false
        private var holdTimer: Timer?

        override var mouseDownCanMoveWindow: Bool {
            return false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }

        override var intrinsicContentSize: NSSize {
            return NSSize(width: NSView.noIntrinsicMetric, height: 36)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let localPoint = superview != nil ? convert(point, from: superview) : point
            guard bounds.contains(localPoint) else { return nil }
            var interactiveTrailingWidth: CGFloat = 0
            if showsCloseButton && showsSpeakerButton {
                interactiveTrailingWidth = 46
            } else if showsCloseButton || showsSpeakerButton {
                interactiveTrailingWidth = 28
            }
            if interactiveTrailingWidth > 0 && localPoint.x >= (bounds.width - interactiveTrailingWidth) {
                return nil
            }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            startLocation = event.locationInWindow
            isDragging = false
            holdTimer?.invalidate()
            if enableDrag {
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
                    guard let self = self, !self.isDragging else { return }
                    self.isDragging = true
                    self.window?.isMovable = false
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    self.onDragStarted?()
                }
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard enableDrag else { return }
            let current = event.locationInWindow
            let deltaX = current.x - startLocation.x
            let deltaY = current.y - startLocation.y
            let dist = hypot(deltaX, deltaY)

            if dist >= 3 {
                if !isDragging {
                    holdTimer?.invalidate()
                    holdTimer = nil
                    isDragging = true
                    window?.isMovable = false
                    onDragStarted?()
                }
                onDragChanged?(deltaX, -deltaY)
            }
        }

        override func mouseUp(with event: NSEvent) {
            holdTimer?.invalidate()
            holdTimer = nil
            window?.isMovable = true
            if enableDrag && isDragging {
                isDragging = false
                onDragEnded?()
            } else {
                let localPoint = convert(event.locationInWindow, from: nil)
                if bounds.contains(localPoint) {
                    onSelect?()
                }
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            holdTimer?.invalidate()
            holdTimer = nil
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
        if !item.isHistoryVisit {
            HistoryManager.shared.recordSearch(query: item.query)
        }
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
                Image(systemName: item.isHistoryVisit ? "safari" : (item.isRecentSearch ? "clock.arrow.circlepath" : "magnifyingglass"))
                    .font(.system(size: 12))
                    .foregroundColor(item.isHistoryVisit ? .accentColor : (item.isRecentSearch ? .accentColor : .secondary))
                    .frame(width: 16)

                Text(item.query)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if item.isHistoryVisit {
                    Text(item.displayURL)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                } else if item.isRecentSearch {
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
            if isSelected && isAnyTabDragging {
                RoundedRectangle(cornerRadius: pillCornerRadius)
                    .fill(Color.primary.opacity(isBeingDragged ? 0.14 : 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: pillCornerRadius)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            } else if isHovered && !isSelected {
                RoundedRectangle(cornerRadius: pillCornerRadius)
                    .fill(Color.primary.opacity(0.04))
            }

            HStack(spacing: 5) {
                if iconSize > 0 {
                    if tab.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: iconSize, height: iconSize)
                    } else if tab.isInternal {
                        Image(systemName: "gearshape")
                            .font(.system(size: iconSize * 0.8))
                            .foregroundColor(isSelected ? .primary : .secondary)
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
        if tab.isInternal {
            return "Settings"
        }
        if let host = tab.currentURL?.host {
            return host
        }
        return "New Tab"
    }
}


