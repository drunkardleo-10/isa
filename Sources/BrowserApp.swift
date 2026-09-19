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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
