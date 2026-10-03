import SwiftUI
import AppKit

enum ProfilePalette {
    static let ground = Color(nsColor: NSColor.windowBackgroundColor)
    static let ink = Color(nsColor: NSColor.labelColor)
    static let muted = Color(nsColor: NSColor.secondaryLabelColor)
    static let faint = Color(nsColor: NSColor.tertiaryLabelColor)
    static let hairline = Color(nsColor: NSColor.separatorColor)
    static let wash = Color(nsColor: NSColor.controlBackgroundColor)
    static let hover = Color.primary.opacity(0.08)
}

struct ProfilePill: View {
    let title: String
    var filled: Bool = false
    var tint: Color = ProfilePalette.ink
    let action: () -> Void

    @State private var hovering: Bool = false

    init(_ title: String, filled: Bool = false, tint: Color = ProfilePalette.ink, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(filled ? Color(nsColor: .windowBackgroundColor) : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? ProfilePalette.ink : (hovering ? ProfilePalette.hover : ProfilePalette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : ProfilePalette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

struct ProfileSegmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    var wide: Bool = false

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Text(title)
                    .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? ProfilePalette.ink : ProfilePalette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: !wide, vertical: false)
                    .frame(maxWidth: wide ? .infinity : nil)
                    .padding(.horizontal, wide ? 4 : 10)
                    .padding(.vertical, 5)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(ProfilePalette.ground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chosenProfileSegment", in: slide)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(2)
        .background(ProfilePalette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: selection)
    }
}

struct ProfileDot: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var hovering: Bool = false
    @State private var shown: (key: String, symbol: String)?

    static let width: CGFloat = 26

    private var symbol: String {
        viewModel.makingProfile ? "plus" : viewModel.profile.symbol
    }

    private var key: String {
        viewModel.makingProfile ? "new" : "\(viewModel.profileID.uuidString)-\(viewModel.profile.symbol)"
    }

    private var isSidebar: Bool {
        viewModel.tabPlacement == .left
    }

    var body: some View {
        Button {
            ProfileMenu.show(for: viewModel)
        } label: {
            ZStack {
                Image(systemName: shown?.symbol ?? symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovering ? ProfilePalette.ink : ProfilePalette.muted)
                    .id(shown?.key ?? key)
                    .transition(.push(from: isSidebar
                        ? (viewModel.profileStep > 0 ? .trailing : .leading)
                        : (viewModel.profileStep > 0 ? .bottom : .top)))
            }
            .frame(width: ProfileDot.width, height: 26)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? ProfilePalette.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(viewModel.profile.name) — ⌃1–⌃9, or two fingers \(isSidebar ? "sideways" : "up or down") over the tabs, to switch")
        .onChange(of: key) { _, now in
            let sym = symbol
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    shown = (now, sym)
                }
            }
        }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

@MainActor
enum ProfileMenu {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static var actions: [Action] = []

    private static func item(_ title: String, key: String = "", checked: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = Action(run)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: key)
        item.target = action
        item.keyEquivalentModifierMask = key.isEmpty ? [] : .control
        item.state = checked ? .on : .off
        return item
    }

    static func show(for viewModel: BrowserViewModel) {
        actions = []
        let menu = NSMenu()
        for (index, profile) in viewModel.profiles.enumerated() {
            let entry = item(profile.name, key: index < 9 ? "\(index + 1)" : "", checked: profile.id == viewModel.profileID) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    viewModel.switchProfile(to: profile.id)
                }
            }
            entry.image = NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("New Profile…") {
            viewModel.askForProfile()
        })
        menu.addItem(.separator())
        let here = viewModel.profile
        menu.addItem(item("Rename “\(here.name)”…") {
            Ask.name("Rename Profile", placeholder: here.name, initial: here.name, confirm: "Rename") {
                viewModel.renameProfile(here.id, to: $0)
            }
        })
        let icons = NSMenu()
        for (symbol, name) in zip(Profiles.icons, Profiles.iconNames) {
            let choice = item(name, checked: here.symbol == symbol) {
                viewModel.setProfileIcon(here.id, to: symbol)
            }
            choice.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
            icons.addItem(choice)
        }
        let iconItem = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        iconItem.submenu = icons
        menu.addItem(iconItem)

        if let at = viewModel.profiles.firstIndex(where: { $0.id == here.id }) {
            if at > 0 {
                menu.addItem(item("Move Left") {
                    viewModel.moveProfile(here.id, to: at - 1)
                })
            }
            if at < viewModel.profiles.count - 1 {
                menu.addItem(item("Move Right") {
                    viewModel.moveProfile(here.id, to: at + 1)
                })
            }
        }


        if !here.isFirst {
            menu.addItem(.separator())
            menu.addItem(item("Delete “\(here.name)”…") {
                Ask.sure("Delete “\(here.name)”?", detail: "Its tabs close, and its cookies and sign-ins are erased from this Mac. History and bookmarks stay.", confirm: "Delete") {
                    viewModel.deleteProfile(here.id)
                }
            })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

@MainActor
enum Ask {
    static func name(_ title: String, placeholder: String, initial: String = "", confirm: String, then: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        show(alert) { ok in
            let val = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if ok, !val.isEmpty {
                then(val)
            }
        }
    }

    static func newProfile(then: @escaping (String, Bool) -> Void, cancelled: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "New Profile"
        alert.informativeText = "Its own tabs. Signed in where your other profiles are, unless it starts afresh."
        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        field.placeholderString = "Work"
        let fresh = NSButton(checkboxWithTitle: "Start signed out, with its own cookies", target: nil, action: nil)
        fresh.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(field)
        box.addSubview(fresh)
        alert.accessoryView = box
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        show(alert) { ok in
            let val = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ok, !val.isEmpty else {
                cancelled()
                return
            }
            then(val, fresh.state != .on)
        }
    }

    static func sure(_ title: String, detail: String, confirm: String, then: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: confirm).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        show(alert) { ok in
            if ok {
                then()
            }
        }
    }

    private static func show(_ alert: NSAlert, _ done: @escaping (Bool) -> Void) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            done(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) {
            done($0 == .alertFirstButtonReturn)
        }
    }
}

struct NewProfileCard: View {
    @ObservedObject var viewModel: BrowserViewModel
    var inline: Bool = false
    @State private var choosing: Bool = false
    @State private var hovering: Bool = false
    @State private var pickedManually: Bool = false
    @FocusState private var typing: Bool

    private var saying: String {
        viewModel.newProfileShared ? "Signed in wherever your other profiles are." : "Its own cookies and sign-ins, starting from none."
    }

    var body: some View {
        Group {
            if inline {
                HStack(spacing: 8) {
                    pick(size: 13, box: CGSize(width: 28, height: 26))
                    field
                        .frame(width: 170)
                    ProfileSegmented(options: [(true, "Signed in"), (false, "Signed out")], selection: $viewModel.newProfileShared)
                        .fixedSize()
                        .help(saying)
                    ProfilePill("Cancel") { cancel() }
                    ProfilePill("Create", filled: true) { create() }
                }
                .frame(height: 38)
            } else {
                VStack(spacing: 12) {
                    pick(size: 20, box: CGSize(width: 44, height: 40))
                    VStack(spacing: 4) {
                        Text("New profile")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ProfilePalette.ink)
                        Text("Its own tabs.")
                            .font(.system(size: 11))
                            .foregroundStyle(ProfilePalette.muted)
                            .multilineTextAlignment(.center)
                    }
                    field
                    VStack(spacing: 6) {
                        ProfileSegmented(options: [(true, "Signed in"), (false, "Signed out")], selection: $viewModel.newProfileShared, wide: true)
                        Text(saying)
                            .font(.system(size: 11))
                            .foregroundStyle(ProfilePalette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        ProfilePill("Cancel") { cancel() }
                        ProfilePill("Create", filled: true) { create() }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if viewModel.newProfileIcon.isEmpty {
                viewModel.newProfileIcon = viewModel.freeIcon
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                typing = true
            }
        }
        .onExitCommand(perform: cancel)
    }

    private func pick(size: CGFloat, box: CGSize) -> some View {
        Button {
            choosing = true
        } label: {
            Image(systemName: viewModel.newProfileIcon.isEmpty ? viewModel.freeIcon : viewModel.newProfileIcon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(ProfilePalette.ink)
                .frame(width: box.width, height: box.height)
                .background(
                    RoundedRectangle(cornerRadius: inline ? 8 : 10, style: .continuous)
                        .fill(hovering || choosing ? ProfilePalette.hover : .clear)
                )
                .contentShape(Rectangle())
                .id(viewModel.newProfileIcon)
                .transition(.opacity)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(inline ? "New profile — choose its icon" : "Choose an icon")
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            icons
        }
    }

    private var field: some View {
        TextField(inline ? "New profile" : "Name", text: $viewModel.newProfileName)
            .textFieldStyle(.plain)
            .font(.system(size: inline ? 12.5 : 13))
            .padding(.horizontal, 10)
            .frame(height: inline ? 26 : 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ProfilePalette.wash))
            .focused($typing)
            .onSubmit(create)
            .onChange(of: viewModel.newProfileName) { _, newName in
                suggestIcon(for: newName)
            }
    }

    private var icons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6), spacing: 4) {
            ForEach(Array(zip(Profiles.icons, Profiles.iconNames)), id: \.0) { symbol, iconName in
                let currentIcon = viewModel.newProfileIcon.isEmpty ? viewModel.freeIcon : viewModel.newProfileIcon
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(symbol == currentIcon ? ProfilePalette.ink : ProfilePalette.muted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(symbol == currentIcon ? ProfilePalette.wash : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        pickedManually = true
                        viewModel.newProfileIcon = symbol
                        choosing = false
                        typing = true
                    }
                    .help(iconName)
            }
        }
        .padding(10)
    }

    private func suggestIcon(for query: String) {
        guard !pickedManually else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return }
        if q == "art" || q.hasPrefix("art") || q == "paint" || q == "design" || q == "draw" {
            withAnimation(.easeOut(duration: 0.14)) {
                viewModel.newProfileIcon = "paintpalette"
            }
            return
        }
        for (symbol, label) in zip(Profiles.icons, Profiles.iconNames) {
            if label.lowercased() == q || (q.count >= 3 && label.lowercased().hasPrefix(q)) {
                withAnimation(.easeOut(duration: 0.14)) {
                    viewModel.newProfileIcon = symbol
                }
                return
            }
        }
    }

    private func create() {
        let named = viewModel.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else { typing = true; return }
        let chosenIcon = viewModel.newProfileIcon.isEmpty ? viewModel.freeIcon : viewModel.newProfileIcon
        let shared = viewModel.newProfileShared
        viewModel.newProfileName = ""
        viewModel.newProfileIcon = ""
        viewModel.newProfileShared = true
        viewModel.addProfile(named: named, icon: chosenIcon, sharesSignIns: shared)
    }

    private func cancel() {
        viewModel.cancelProfileCreation()
        let back = viewModel.profiles.firstIndex { $0.id == viewModel.profileID } ?? 0
        ProfileSwipe.shared.slide(viewModel, to: back, from: viewModel.profiles.count)
    }
}

@MainActor
final class ProfileSwipe {
    static let shared = ProfileSwipe()

    private weak var viewModel: BrowserViewModel?
    private var monitor: Any?
    private enum Axis { case undecided, across, along }
    private var axis = Axis.undecided
    private var tracking = false
    private var gliding = false
    private var gathered = CGSize.zero
    private var notched = Date.distantPast
    private var resting = Date.distantPast
    private var ignoring = false

    static let rest: TimeInterval = 0.4

    static func enough(for viewModel: BrowserViewModel) -> CGFloat {
        viewModel.tabPlacement == .left ? 50 : 38 * 0.6
    }

    func start(for viewModel: BrowserViewModel) {
        self.viewModel = viewModel
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            return self.takes(event) ? nil : event
        }
    }

    private func overTabs(_ event: NSEvent, in vm: BrowserViewModel) -> Bool {
        guard let window = event.window, window === NSApp.keyWindow || window === NSApp.mainWindow else { return false }
        if vm.tabPlacement == .left {
            let width: CGFloat = vm.isSidebarCollapsed ? 48 : 240
            return event.locationInWindow.x < width
        }
        return event.locationInWindow.y > window.frame.height - 44
    }

    private func takes(_ event: NSEvent) -> Bool {
        guard let vm = viewModel, vm.usesProfiles else { return false }

        if !event.hasPreciseScrollingDeltas {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let isSidebar = vm.tabPlacement == .left
            let step = isSidebar ? (abs(dx) > abs(dy) ? dx : 0) : dy
            guard step != 0, overTabs(event, in: vm) else { return false }
            let now = Date()
            let rested = now.timeIntervalSince(notched) > 0.3 && now > resting
            notched = now
            guard rested else { return true }
            let here = vm.makingProfile ? vm.profiles.count : (vm.profiles.firstIndex { $0.id == vm.profileID } ?? 0)
            let target = here + (step < 0 ? 1 : -1)
            if target >= 0, target <= vm.profiles.count {
                slide(vm, to: target, from: here)
            }
            return true
        }

        if !event.momentumPhase.isEmpty { return gliding }

        switch event.phase {
        case .began:
            gliding = false
            ignoring = false
            guard overTabs(event, in: vm) else {
                tracking = false
                return false
            }
            began()
            if ignoring { return true }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .changed:
            if ignoring { return true }
            guard tracking else { return false }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .ended, .cancelled:
            if ignoring {
                ignoring = false
                gliding = true
                return true
            }
            guard tracking else { return false }
            let taken = axis == .across
            ended(cancelled: event.phase == .cancelled)
            gliding = taken
            return taken
        default:
            return false
        }
    }

    func began() {
        axis = .undecided
        gathered = .zero
        ignoring = Date() <= resting
        tracking = !ignoring
    }

    @discardableResult
    func moved(dx: CGFloat, dy: CGFloat) -> Bool {
        guard tracking, let vm = viewModel else { return false }
        let (step, aside) = vm.tabPlacement == .left ? (dx, dy) : (dy, dx)
        gathered.width += step
        gathered.height += aside
        if axis == .undecided {
            guard abs(gathered.width) + abs(gathered.height) > 6 else { return false }
            axis = abs(gathered.width) > abs(gathered.height) * 1.5 ? .across : .along
        }
        guard axis == .across else { return false }
        vm.profileSwipe = resisted(gathered.width, in: vm)
        return true
    }

    func ended(cancelled: Bool = false) {
        defer { tracking = false }
        guard let vm = viewModel, axis == .across else { return }
        let travel = gathered.width
        let here = vm.makingProfile ? vm.profiles.count : (vm.profiles.firstIndex { $0.id == vm.profileID } ?? 0)
        let target = cancelled || abs(travel) < ProfileSwipe.enough(for: vm) ? here : here + (travel < 0 ? 1 : -1)
        guard target != here, target >= 0, target <= vm.profiles.count else {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                vm.profileSwipe = 0
            }
            return
        }
        slide(vm, to: target, from: here)
    }

    private func resisted(_ travel: CGFloat, in vm: BrowserViewModel) -> CGFloat {
        let here = vm.makingProfile ? vm.profiles.count : (vm.profiles.firstIndex { $0.id == vm.profileID } ?? 0)
        let blocked = (travel > 0 && here == 0) || (travel < 0 && here == vm.profiles.count)
        return blocked ? travel / 4 : travel
    }

    func slide(_ vm: BrowserViewModel, to target: Int, from here: Int) {
        if vm.makingProfile, target != vm.profiles.count {
            vm.cancelProfileCreation()
        }
        let width = vm.tabPlacement == .left ? (vm.isSidebarCollapsed ? 48.0 : 240.0) : 38.0
        let away: CGFloat = target > here ? -1 : 1
        vm.profileStep = target > here ? 1 : -1
        resting = Date().addingTimeInterval(ProfileSwipe.rest)
        withAnimation(.easeOut(duration: 0.22)) {
            vm.profileSwipe = away * width
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                if target == vm.profiles.count {
                    vm.makingProfile = true
                } else {
                    vm.makingProfile = false
                    vm.switchProfile(to: vm.profiles[target].id)
                }
                vm.profileSwipe = 0
            }
        }
    }
}
