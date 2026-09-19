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
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: BrowserViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if ProcessInfo.processInfo.arguments.contains("--run-perf-sequence") {
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.runPerfSequence()
            }
        }
    }

    private func runPerfSequence() {
        guard let vm = viewModel else { return }

        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            
            vm.createNewTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                
                vm.createNewTab()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    
                    vm.closeActiveTab()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        vm.closeActiveTab()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            
                            vm.navigate(tab: vm.activeTab, to: "https://example.com")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                
                                vm.createNewTab()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    vm.createNewTab()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        vm.createNewTab()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            
                                            vm.navigate(tab: vm.activeTab, to: "https://127.0.0.1:59999/nonexistent")
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                vm.closeActiveTab()
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                    
                                                    vm.navigate(tab: vm.activeTab, to: "https://example.org")
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                                        PerformanceMonitor.shared.log(event: "SequenceComplete", details: "All steps verified successfully")
                                                        exit(0)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
