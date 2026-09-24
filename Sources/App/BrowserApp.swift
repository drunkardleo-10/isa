import SwiftUI
import AppKit

@main
struct BrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(viewModel.theme.colorScheme)
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    viewModel.createNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") {
                    viewModel.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Tab") {
                Button(viewModel.activeTab.isMuted ? "Unmute Tab" : "Mute Tab") {
                    viewModel.toggleMuteActiveTab()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Button("Run 25 Tab Benchmark") {
                    appDelegate.runPerfSequence()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Open 25 Sample Tabs") {
                    viewModel.openSampleTabs(count: 25)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])


                Divider()

                ForEach(1...9, id: \.self) { num in
                    Button("Select Tab \(num)") {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            viewModel.selectTabNumber(num)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(num)")), modifiers: .command)
                }
            }

            CommandMenu("Navigation") {
                Button("Open Location…") {
                    viewModel.focusAddressBar()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Reload Page") {
                    viewModel.reloadActiveTab()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Back") {
                    viewModel.goBackActiveTab()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!viewModel.activeTab.canGoBack)

                Button("Forward") {
                    viewModel.goForwardActiveTab()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!viewModel.activeTab.canGoForward)
            }

            CommandMenu("Find") {
                Button("Find in Page…") {
                    viewModel.toggleFindInPage()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    viewModel.findNextInPage()
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    viewModel.findPreviousInPage()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            CommandMenu("History") {
                Button("Show Full History") {
                    viewModel.showHistoryView()
                }
                .keyboardShortcut("y", modifiers: .command)

                Button("Clear Browsing Data…") {
                    viewModel.showHistoryView()
                }

                Divider()

                let recent = Array(HistoryManager.shared.historyItems.prefix(8))
                if recent.isEmpty {
                    Text("No Recent History")
                } else {
                    ForEach(recent) { item in
                        Button(item.displayTitle) {
                            if let url = URL(string: item.url) {
                                viewModel.openHistoryURL(url)
                            }
                        }
                    }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: BrowserViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let icon = NSImage(named: "AppIcon")
            ?? (Bundle.main.path(forResource: "AppIcon", ofType: "icns").flatMap { NSImage(contentsOfFile: $0) })
            ?? NSImage(contentsOfFile: "Assets/AppIcon.icns") {
            NSApp.applicationIconImage = icon
        }

        if ProcessInfo.processInfo.arguments.contains("--run-perf-sequence") ||
           ProcessInfo.processInfo.arguments.contains("--open-tabs") ||
           ProcessInfo.processInfo.arguments.contains("--benchmark") ||
           ProcessInfo.processInfo.environment["ISA_BENCHMARK"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.runPerfSequence()
            }
        }
    }

    func runPerfSequence() {
        guard let vm = viewModel else { return }
        vm.openSampleTabs(count: 25, delayPerTab: 3.0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let sleepingTabs = vm.tabs.filter { $0.isSleeping }
                if let first = sleepingTabs.first {
                    vm.selectTab(id: first.id)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if sleepingTabs.count > 1 {
                        vm.selectTab(id: sleepingTabs[1].id)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if let first = sleepingTabs.first {
                            vm.selectTab(id: first.id)
                        }
                        if ProcessInfo.processInfo.arguments.contains("--exit-on-finish") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                exit(0)
                            }
                        }
                    }
                }
            }
        }
    }
}
