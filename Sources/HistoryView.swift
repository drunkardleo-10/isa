import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var historyManager: HistoryManager = HistoryManager.shared
    @State private var searchText: String = ""
    @State private var showClearSheet: Bool = false
    @State private var isClearHovered: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var escMonitor: Any? = nil

    private var filteredItems: [HistoryItem] {
        historyManager.search(query: searchText)
    }

    private var groupedItems: [(String, [HistoryItem])] {
        historyManager.groupedHistory(for: filteredItems)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.dismissHistoryView()
                }

            VStack(spacing: 0) {
                headerView
                Divider()
                    .opacity(0.4)

                if historyManager.historyItems.isEmpty {
                    emptyHistoryView
                } else if filteredItems.isEmpty {
                    emptySearchView
                } else {
                    historyListView
                }
            }
            .frame(width: 640, height: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 12)
            .sheet(isPresented: $showClearSheet) {
                ClearBrowsingDataSheet(historyManager: historyManager, isPresented: $showClearSheet)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            let vm = viewModel
            if escMonitor == nil {
                escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak vm] event in
                    guard let vm = vm else { return event }
                    if event.keyCode == 53 {
                        if showClearSheet {
                            showClearSheet = false
                        } else {
                            vm.dismissHistoryView()
                        }
                        return nil
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
        }
        .onExitCommand {
            if showClearSheet {
                showClearSheet = false
            } else {
                viewModel.dismissHistoryView()
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))

                Text("\(filteredItems.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Search history…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)
                    .onExitCommand {
                        viewModel.dismissHistoryView()
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 220)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            Button(action: {
                showClearSheet = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(historyManager.historyItems.isEmpty ? .secondary.opacity(0.4) : .red.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(Color.red.opacity(isClearHovered && !historyManager.historyItems.isEmpty ? 0.14 : 0.08))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Clear browsing data")
            .disabled(historyManager.historyItems.isEmpty)
            .onHover { isClearHovered = $0 }

            Button(action: {
                viewModel.dismissHistoryView()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(Color.primary.opacity(0.06))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var historyListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groupedItems, id: \.0) { groupName, items in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(groupName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(items.count)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                        VStack(spacing: 1) {
                            ForEach(items) { item in
                                HistoryRowView(
                                    item: item,
                                    onSelect: { inNewTab in
                                        if let url = URL(string: item.url) {
                                            viewModel.openHistoryURL(url, inNewTab: inNewTab)
                                        }
                                    },
                                    onDelete: {
                                        historyManager.deleteItem(id: item.id)
                                    }
                                )
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                }
            }
            .padding(14)
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.4))

            Text("No Browsing History")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Text("Websites you visit will appear here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))

            Text("No Results Found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Text("No history matching \"\(searchText)\"")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct ClearBrowsingDataSheet: View {
    @ObservedObject var historyManager: HistoryManager
    @Binding var isPresented: Bool
    @State private var selectedRange: ClearHistoryRange = .allTime
    @Namespace private var pillNamespace

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clear Browsing Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Choose the time range of history you wish to clear.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 3) {
                ForEach(ClearHistoryRange.allCases) { range in
                    RangeOptionRow(
                        range: range,
                        isSelected: selectedRange == range,
                        namespace: pillNamespace,
                        onSelect: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedRange = range
                            }
                        }
                    )
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selectedRange)

            HStack {
                ModernCancelButton {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                ModernDestructiveButton(title: "Clear History") {
                    historyManager.clearHistory(range: selectedRange)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            isPresented = false
        }
    }
}

struct RangeOptionRow: View {
    let range: ClearHistoryRange
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(range.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: Color.accentColor.opacity(0.08), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "activeRangePill", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct ModernCancelButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Text("Cancel")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 3 : 1.5, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(isHovered ? 0.16 : 0.10), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct ModernDestructiveButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    LinearGradient(
                        colors: isHovered
                            ? [Color(red: 0.95, green: 0.28, blue: 0.26), Color(red: 0.82, green: 0.16, blue: 0.16)]
                            : [Color(red: 0.90, green: 0.24, blue: 0.22), Color(red: 0.78, green: 0.13, blue: 0.13)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 5)
                        Spacer()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color.red.opacity(isHovered ? 0.35 : 0.22), radius: isHovered ? 5 : 3, x: 0, y: isHovered ? 2 : 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct HistoryRowView: View {
    let item: HistoryItem
    let onSelect: (_ inNewTab: Bool) -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var favicon: NSImage? = nil

    var body: some View {
        Button(action: {
            let inNewTab = NSEvent.modifierFlags.contains(.command)
            onSelect(inNewTab)
        }) {
            HStack(spacing: 10) {
                if let fav = favicon {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .cornerRadius(2)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 15, height: 15)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(item.host)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(item.formattedTime)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
                .help("Delete from history")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            loadFavicon()
        }
        .contextMenu {
            Button("Open in Current Tab") {
                onSelect(false)
            }
            Button("Open in New Tab") {
                onSelect(true)
            }
            Divider()
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }
            Divider()
            Button("Delete from History", role: .destructive) {
                onDelete()
            }
        }
    }

    private func loadFavicon() {
        guard let host = URL(string: item.url)?.host, !host.isEmpty else { return }
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
        guard let url = faviconURL else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.favicon = img
            }
        }.resume()
    }
}
