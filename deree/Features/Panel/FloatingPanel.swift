import AppKit

@MainActor
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear

        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    func slideIn() {
        guard let screen = NSScreen.main else { return }
        let targetFrame = PanelConstants.frame(for: screen)

        var startFrame = targetFrame
        startFrame.origin.x = screen.visibleFrame.maxX
        setFrame(startFrame, display: false)
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
        }
    }

    func slideOut(completion: @MainActor @Sendable @escaping () -> Void = {}) {
        guard let screen = NSScreen.main else {
            orderOut(nil)
            completion()
            return
        }

        var offscreenFrame = frame
        offscreenFrame.origin.x = screen.visibleFrame.maxX

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(offscreenFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                completion()
            }
        })
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
