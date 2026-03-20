import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear

        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        hidesOnDeactivate = false

        positionAtRightEdge()
    }

    private func positionAtRightEdge() {
        guard let screen = NSScreen.main else { return }
        setFrame(PanelConstants.frame(for: screen), display: true)
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
