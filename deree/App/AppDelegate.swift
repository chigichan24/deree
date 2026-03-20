import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store(initialState: AppReducer.State()) {
        AppReducer()
    }

    private var floatingPanel: FloatingPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var deactivateObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupFloatingPanel()
        store.send(.appDidFinishLaunching)

        _ = observe { [weak self] in
            guard let self else { return }
            let isVisible = store.panel.isPanelVisible
            if isVisible {
                floatingPanel?.slideIn()
            } else {
                floatingPanel?.slideOut {}
            }
        }
    }

    // MARK: - Floating Panel

    private func setupFloatingPanel() {
        guard let screen = NSScreen.main else { return }

        let panel = FloatingPanel(contentRect: PanelConstants.frame(for: screen))
        let panelView = ClipboardImageListView(
            store: store.scope(state: \.clipboard, action: \.clipboard)
        )
        panel.contentView = NSHostingView(rootView: panelView)
        panel.delegate = self
        floatingPanel = panel

        // queue: .main guarantees Main Thread, enabling MainActor.assumeIsolated
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionPanel()
            }
        }

        // Hide panel when app loses focus
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.store.send(.panel(.hidePanel))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = deactivateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        screenObserver = nil
        deactivateObserver = nil
    }

    private func repositionPanel() {
        guard let screen = NSScreen.main, let panel = floatingPanel else { return }
        panel.setFrame(PanelConstants.frame(for: screen), display: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        store.send(.panel(.hidePanel))
    }
}
