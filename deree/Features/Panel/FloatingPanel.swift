import AppKit

@MainActor
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // Borderless panel: no .titled so there is no title bar offset
            // that would misalign SwiftUI hit-testing coordinates.
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear

        acceptsMouseMovedEvents = true
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
        // .nonactivatingPanel prevents deactivating the frontmost app,
        // while makeKey is required so SwiftUI's onHover (NSTrackingArea
        // with activeInKeyWindow) and button clicks work in this panel.
        makeKeyAndOrderFront(nil)

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
