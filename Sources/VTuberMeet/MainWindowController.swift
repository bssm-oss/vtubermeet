import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private let mainViewController = MainViewController()
    private var alwaysOnTop = false
    private var companionMode = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VTuberMeet"
        window.center()
        window.minSize = NSSize(width: 1060, height: 780)
        window.backgroundColor = Design.parchment
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        super.init(window: window)
        window.contentViewController = mainViewController
        mainViewController.windowController = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        alwaysOnTop = enabled
        updateWindowLevel()
    }

    func setCompanionMode(_ enabled: Bool) {
        companionMode = enabled
        mainViewController.setCompanionMode(enabled)
        updateWindowLevel()

        guard let window else { return }
        let newSize = enabled ? NSSize(width: 520, height: 720) : NSSize(width: 1120, height: 820)
        var frame = window.frame
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: true)
    }

    private func updateWindowLevel() {
        window?.level = (alwaysOnTop || companionMode) ? .floating : .normal
    }
}
