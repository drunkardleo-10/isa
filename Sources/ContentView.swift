import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                ForEach(viewModel.tabs) { tab in
                    WebView(tab: tab)
                        .opacity(tab.id == viewModel.selectedTabId && !tab.isNewTabState ? 1 : 0)
                        .allowsHitTesting(tab.id == viewModel.selectedTabId && !tab.isNewTabState && !tab.isAddressOverlayPresented)
                }

                ActiveTabOverlayView(tab: viewModel.activeTab, viewModel: viewModel)
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor())
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(viewModel.tabs) { tab in
                        TabPillView(
                            tab: tab,
                            viewModel: viewModel,
                            isSelected: tab.id == viewModel.selectedTabId
                        )
                    }

                    Button(action: {
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
            }

            WindowDragHandle()
                .frame(height: 32)

            Button(action: {
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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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

struct ActiveTabOverlayView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var viewModel: BrowserViewModel
    @FocusState private var isFocused: Bool
    @State private var addressInput: String = ""

    var body: some View {
        if tab.isNewTabState || tab.isAddressOverlayPresented {
            ZStack {
                if tab.isAddressOverlayPresented && !tab.isNewTabState {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture {
                            viewModel.dismissAddressBar()
                        }
                }

                VStack {
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
                                submitNavigation()
                            }
                            .onExitCommand {
                                if !tab.isNewTabState {
                                    viewModel.dismissAddressBar()
                                }
                            }

                        if !addressInput.isEmpty {
                            Button(action: {
                                addressInput = ""
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

                    Spacer()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            .onAppear {
                syncInput()
                isFocused = true
            }
            .onChange(of: tab.id) { _ in
                syncInput()
                isFocused = true
            }
            .onChange(of: tab.isAddressOverlayPresented) { isPresented in
                if isPresented {
                    syncInput()
                    isFocused = true
                }
            }
        }
    }

    private func syncInput() {
        if let url = tab.currentURL {
            addressInput = url.absoluteString
        } else {
            addressInput = tab.addressText
        }
    }

    private func submitNavigation() {
        let text = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.navigate(tab: tab, to: text)
    }
}

struct TabPillView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var viewModel: BrowserViewModel
    let isSelected: Bool

    @State private var isHovered: Bool = false
    @State private var isDropTargeted: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
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
                .frame(minWidth: 40, maxWidth: 160, alignment: .leading)

            Button(action: {
                viewModel.closeTab(id: tab.id)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isDropTargeted ? Color.accentColor : (isSelected ? Color.primary.opacity(0.06) : Color.clear), lineWidth: isDropTargeted ? 1.5 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture {
            if isSelected && !tab.isNewTabState {
                viewModel.focusAddressBar()
            } else {
                viewModel.selectTab(id: tab.id)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedIdString = items.first,
                  let draggedUUID = UUID(uuidString: draggedIdString),
                  let fromIndex = viewModel.tabs.firstIndex(where: { $0.id == draggedUUID }),
                  let toIndex = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                  fromIndex != toIndex else {
                return false
            }
            _ = withAnimation(.easeInOut(duration: 0.2)) {
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

    private var backgroundColor: Color {
        if isSelected {
            return Color.primary.opacity(0.08)
        }
        if isHovered {
            return Color.primary.opacity(0.04)
        }
        return Color.clear
    }
}
