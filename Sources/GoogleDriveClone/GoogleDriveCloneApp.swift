import AppKit
import SwiftUI

@main
struct GoogleDriveCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = SyncCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        setApplicationMenuTitle()

        DispatchQueue.main.async {
            self.setApplicationMenuTitle()
            NSApplication.shared.windows.first?.title = "SkyVault for Google"
        }
    }

    @MainActor
    private func setApplicationMenuTitle() {
        NSApplication.shared.mainMenu?.items.first?.title = "SkyVault for Google"
    }
}
