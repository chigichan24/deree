import AppKit

@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private let onLeftClick: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void

    init(onLeftClick: @MainActor @escaping () -> Void, onQuit: @MainActor @escaping () -> Void) {
        self.onLeftClick = onLeftClick
        self.onQuit = onQuit
        setupStatusItem()
    }

    func updateIcon(active: Bool) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: active ? "photo.on.rectangle.fill" : "photo.on.rectangle",
            accessibilityDescription: "deree"
        )
    }

    // MARK: - Private

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "photo.on.rectangle",
                accessibilityDescription: "deree"
            )
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onLeftClick()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let quitItem = menu.addItem(withTitle: "Quit deree", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func quitApp() {
        onQuit()
    }
}
