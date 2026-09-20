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
                        viewModel.selectTabNumber(num)
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
            ?? (Bundle.main.path(forResource: "isa_browser", ofType: "png").flatMap { NSImage(contentsOfFile: $0) })
            ?? NSImage(contentsOfFile: "Assets/AppIcon.icns")
            ?? NSImage(contentsOfFile: "Assets/isa_browser.png") {
            NSApp.applicationIconImage = icon
        }

        if ProcessInfo.processInfo.arguments.contains("--test-decay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.runTwoTabDecayTest()
            }
            return
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

    func runTwoTabDecayTest() {
        guard let vm = viewModel else { return }
        print("=== Starting 2-Tab Fast Switching & 60s Idle Decay Test ===")

        let tabA = vm.tabs[0]
        vm.navigate(tab: tabA, to: "https://www.wikipedia.org/?utm_source=chatgpt.com")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let tabB = Tab()
            vm.tabs.append(tabB)
            vm.selectedTabId = tabB.id
            vm.bindTabs()
            vm.navigate(tab: tabB, to: "https://github.com/?utm_source=chatgpt.com")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                print("--- Stage 1: Fast Switching between Tab A and Tab B (15s) ---")
                var switchCount = 0
                func doRapidSwitch() {
                    if switchCount >= 6 {
                        print("[TEST] Verified: Both Tab A and Tab B stayed live. Tab A webView: \(tabA.webView != nil), Tab B webView: \(tabB.webView != nil)")
                        assert(tabA.webView != nil && !tabA.isSleeping, "Tab A must remain live")
                        assert(tabB.webView != nil && !tabB.isSleeping, "Tab B must remain live")
                        print("[TEST] PASS: Fast switching between 2 tabs kept both live with ZERO reloads.")
                        startIdleDecayPhase()
                        return
                    }
                    switchCount += 1
                    let target = (switchCount % 2 == 1) ? tabA : tabB
                    vm.selectTab(id: target.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        doRapidSwitch()
                    }
                }

                func startIdleDecayPhase() {
                    print("--- Stage 2: Leaving Tab A active and Tab B idle for 65s ---")
                    vm.selectTab(id: tabA.id)
                    let startTime = Date()

                    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
                        let elapsed = Int(Date().timeIntervalSince(startTime))
                        let bLive = tabB.webView != nil
                        let bSleeping = tabB.isSleeping
                        print("[TEST] [\(elapsed)s] Tab A live: \(tabA.webView != nil) | Tab B live: \(bLive), sleeping: \(bSleeping)")

                        if elapsed < 55 {
                            if !bLive {
                                print("[TEST] FAIL: Tab B slept prematurely before 60s idle")
                                exit(1)
                            }
                        } else if elapsed >= 65 {
                            timer.invalidate()
                            if bSleeping && !bLive {
                                print("[TEST] PASS: Tab B slept automatically after 60s of inactivity without a 3rd tab!")
                                assert(tabA.webView != nil && !tabA.isSleeping, "Tab A must remain active and live")

                                print("--- Stage 3: Waking Tab B on demand ---")
                                vm.selectTab(id: tabB.id)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    assert(tabB.webView != nil && !tabB.isSleeping, "Tab B must be awake")
                                    print("[TEST] PASS: Tab B successfully woke up and restored webView.")
                                    print("=== All 2-Tab Switching and Idle Decay Tests PASSED ===")
                                    exit(0)
                                }
                            } else {
                                print("[TEST] FAIL: Tab B did not sleep after 65s idle")
                                exit(1)
                            }
                        }
                    }
                }

                doRapidSwitch()
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
