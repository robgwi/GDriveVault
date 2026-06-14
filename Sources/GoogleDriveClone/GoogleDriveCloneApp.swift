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
                .onAppear {
                    appDelegate.coordinator = coordinator
                }
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
    weak var coordinator: SyncCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        setApplicationMenuTitle()

        DispatchQueue.main.async {
            self.setApplicationMenuTitle()
            NSApplication.shared.windows.first?.title = "GDriveVault"
        }
    }

    @MainActor
    private func setApplicationMenuTitle() {
        NSApplication.shared.mainMenu?.items.first?.title = "GDriveVault"
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator?.isRunning == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "A sync is still active"
        alert.informativeText = "Stop pauses the live rclone process only while GDriveVault remains open. If you quit now, a later Resume can skip completed files, but any partially uploaded Google Drive file will restart."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep GDriveVault Open")
        alert.addButton(withTitle: "Quit Anyway")

        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
