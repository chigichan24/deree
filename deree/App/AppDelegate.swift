import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store(initialState: AppReducer.State()) {
        AppReducer()
    }

    private var floatingPanel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupFloatingPanel()
        store.send(.appDidFinishLaunching)

        observe { [weak self] in
            guard let self else { return }
            let isVisible = store.panel.isPanelVisible
            if isVisible {
                floatingPanel?.orderFront(nil)
            } else {
                floatingPanel?.orderOut(nil)
            }
        }
    }

    private func setupFloatingPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 280
        let contentRect = NSRect(
            x: screenFrame.maxX - panelWidth,
            y: screenFrame.origin.y,
            width: panelWidth,
            height: screenFrame.height
        )

        let panel = FloatingPanel(contentRect: contentRect)
        let panelView = PanelView(
            store: store.scope(state: \.clipboard, action: \.clipboard)
        )
        panel.contentView = NSHostingView(rootView: panelView)
        panel.delegate = self
        floatingPanel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionPanel()
        }
    }

    private func repositionPanel() {
        guard let screen = NSScreen.main, let panel = floatingPanel else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 280
        let newFrame = NSRect(
            x: screenFrame.maxX - panelWidth,
            y: screenFrame.origin.y,
            width: panelWidth,
            height: screenFrame.height
        )
        panel.setFrame(newFrame, display: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        store.send(.panel(.hidePanel))
    }
}
