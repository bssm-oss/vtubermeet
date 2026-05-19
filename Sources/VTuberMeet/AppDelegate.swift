import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        applyApplicationIcon()
        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func applyApplicationIcon() {
        if applyApplicationIcon(from: Bundle.main.resourceURL) {
            return
        }

        _ = applyApplicationIcon(from: Bundle.module.resourceURL)
    }

    private func applyApplicationIcon(from resourceURL: URL?) -> Bool {
        guard let resourceURL else { return false }

        let candidateURLs = [
            resourceURL.appendingPathComponent("AppIcon.icns"),
            resourceURL.appendingPathComponent("Resources/AppIcon.icns")
        ]

        for url in candidateURLs {
            if let image = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = image
                return true
            }
        }

        return false
    }
}
