import SwiftUI
import AppKit

struct ShortcutsSectionView: View {
    @ObservedObject var manager: ShortcutsManager = ShortcutsManager.shared
    @ObservedObject var viewModel: BrowserViewModel
    let tab: Tab
    let onAddShortcut: () -> Void
    let onEditShortcut: (ShortcutItem) -> Void

    private let columns = [
        GridItem(.fixed(72), spacing: 20),
        GridItem(.fixed(72), spacing: 20),
        GridItem(.fixed(72), spacing: 20)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            ForEach(manager.shortcuts) { item in
                ShortcutTileView(
                    item: item,
                    favicon: manager.favicons[item.id],
                    onSelect: {
                        PerformanceMonitor.shared.log(event: "ShortcutClick", details: "Clicked shortcut \"\(item.title)\" -> \(item.url)")
                        viewModel.navigate(tab: tab, to: item.url)
                    },
                    onOpenInNewTab: {
                        PerformanceMonitor.shared.log(event: "ShortcutNewTab", details: "Opened shortcut in new tab \"\(item.title)\" -> \(item.url)")
                        let newTab = Tab()
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.tabs.append(newTab)
                            viewModel.selectedTabId = newTab.id
                        }
                        viewModel.bindTabs()
                        viewModel.navigate(tab: newTab, to: item.url)
                    },
                    onEdit: {
                        onEditShortcut(item)
                    },
                    onRemove: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            manager.removeShortcut(id: item.id)
                        }
                    }
                )
            }

            if manager.shortcuts.count < ShortcutsManager.maxShortcuts {
                AddShortcutTileView(action: onAddShortcut)
            }
        }
        .frame(width: 72 * 3 + 20 * 2)
    }
}

struct ShortcutTileView: View {
    let item: ShortcutItem
    let favicon: NSImage?
    let onSelect: () -> Void
    let onOpenInNewTab: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.6 : 0.4), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: 4, x: 0, y: 2)
                    .frame(width: 48, height: 48)

                if let favicon = favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                        .frame(width: 48, height: 48)
                } else {
                    Text(item.title.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 48, height: 48)
                }

                if isHovered {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                        )
                        .contentShape(Circle())
                        .onTapGesture {
                            onEdit()
                        }
                        .padding(3)
                        .transition(.opacity)
                }
            }
            .frame(width: 48, height: 48)

            Text(item.title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .help("\(item.title) — \(item.url)")
        .contextMenu {
            Button("Open in New Tab") {
                onOpenInNewTab()
            }
            Button("Edit shortcut") {
                onEdit()
            }
            Divider()
            Button("Remove", role: .destructive) {
                onRemove()
            }
        }
    }
}

struct AddShortcutTileView: View {
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.6 : 0.4), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: 4, x: 0, y: 2)
                    .frame(width: 48, height: 48)

                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .secondary)
            }
            .frame(width: 48, height: 48)

            Text("Add shortcut")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .help("Add a new site shortcut")
    }
}

struct ShortcutEditorModalView: View {
    let editingItem: ShortcutItem?
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var nameInput: String = ""
    @State private var urlInput: String = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isUrlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text(editingItem == nil ? "Add shortcut" : "Edit shortcut")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("e.g. GitHub", text: $nameInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isNameFocused)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .onSubmit {
                            if urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                isUrlFocused = true
                            } else {
                                submitIfValid()
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("URL")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("e.g. github.com", text: $urlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isUrlFocused)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .onSubmit {
                            submitIfValid()
                        }
                }

                HStack(spacing: 8) {
                    if editingItem != nil, let onDelete = onDelete {
                        Button(action: onDelete) {
                            Text("Remove")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                    Button(action: submitIfValid) {
                        Text("Done")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isURLValid ? Color.accentColor : Color.gray.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isURLValid)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 360)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 12)
            .onAppear {
                if let item = editingItem {
                    nameInput = item.title
                    urlInput = item.url
                } else {
                    nameInput = ""
                    urlInput = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isNameFocused = true
                }
            }
    }

    private var isURLValid: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitIfValid() {
        guard isURLValid else { return }
        onSave(nameInput, urlInput)
    }
}

