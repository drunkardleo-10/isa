import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Namespace private var tabNamespace

    private var computedTabWidth: CGFloat {
        let count = viewModel.tabs.count
        if count <= 2 { return 160 }
        if count <= 4 { return 135 }
        if count <= 7 { return 110 }
        if count <= 10 { return 85 }
        return 65
    }

    private var totalTabsContentWidth: CGFloat {
        let count = CGFloat(viewModel.tabs.count)
        let tabWidth = computedTabWidth
        let spacing: CGFloat = 4
        let plusButtonWidth: CGFloat = 26
        return (count * tabWidth) + (count * spacing) + plusButtonWidth + 12
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

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
                        viewModel.selectTabNumber(num)
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
                .frame(width: 80, height: 32)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(viewModel.tabs) { tab in
                            TabPillView(
                                tab: tab,
                                viewModel: viewModel,
                                isSelected: tab.id == viewModel.selectedTabId,
                                tabNamespace: tabNamespace,
                                tabWidth: computedTabWidth
                            )
                            .id(tab.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85).combined(with: .opacity),
                                removal: .scale(scale: 0.85).combined(with: .opacity)
                            ))
                        }

                        Button(action: {
                            PerformanceMonitor.shared.log(event: "Click", details: "New Tab (+) button")
                            viewModel.createNewTab()
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.05))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("New Tab (⌘T)")
                    }
                    .padding(.trailing, 4)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.tabs.map { $0.id })
                }
                .frame(maxWidth: totalTabsContentWidth)
                .onChange(of: viewModel.selectedTabId) { _, newId in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(newId, anchor: .center)
                    }
                }
            }

            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: 32)

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
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {}

    final class DragNSView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct MiddleClickAction: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MiddleClickView, context: Context) {
        nsView.action = action
    }

    final class MiddleClickView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .otherMouseDown, event.buttonNumber == 2 else {
                return nil
            }
            return self
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                action?()
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
                            isFocused = true
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
                    }

                    Spacer()
                }
                .animation(.spring(response: 0.18, dampingFraction: 0.86), value: suggestions.map { $0.id })
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            .onAppear {
                syncInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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

    @State private var isHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isDropTargeted: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 6) {
                if tab.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .cornerRadius(2)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .primary : .secondary)
                }

                Text(displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                PerformanceMonitor.shared.log(event: "Click", details: "Tab pill clicked: \"\(displayTitle)\"")
                if isSelected && !tab.isNewTabState {
                    viewModel.focusAddressBar()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        viewModel.selectTab(id: tab.id)
                    }
                }
            }
            .draggable(tab.id.uuidString)

            Button(action: {
                PerformanceMonitor.shared.log(event: "Click", details: "Tab close button: \"\(displayTitle)\"")
                viewModel.closeTab(id: tab.id)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isCloseHovered ? 0.12 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .onHover { hovering in
                isCloseHovered = hovering
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(width: tabWidth, height: 26)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "activeTabBackground", in: tabNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.04))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isDropTargeted ? Color.accentColor : (isSelected ? Color.primary.opacity(0.06) : Color.clear), lineWidth: isDropTargeted ? 1.5 : 0.5)
        )
        .overlay(
            MiddleClickAction {
                PerformanceMonitor.shared.log(event: "Click", details: "Middle-click closed tab: \"\(displayTitle)\"")
                viewModel.closeTab(id: tab.id)
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .dropDestination(for: String.self) { items, _ in
            guard let draggedIdString = items.first,
                  let draggedUUID = UUID(uuidString: draggedIdString),
                  let fromIndex = viewModel.tabs.firstIndex(where: { $0.id == draggedUUID }),
                  let toIndex = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                  fromIndex != toIndex else {
                return false
            }
            PerformanceMonitor.shared.log(event: "Drag", details: "Tab \"\(displayTitle)\" dropped from [\(fromIndex)] onto [\(toIndex)]")
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.moveTab(from: fromIndex, to: toIndex)
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
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
