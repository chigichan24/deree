import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var floatingPanel: FloatingPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var deactivateObserver: (any NSObjectProtocol)?
    private let onPanelClose: () -> Void
    private let onDeactivate: () -> Void

    init(
        contentView: some View,
        onPanelClose: @escaping () -> Void,
        onDeactivate: @escaping () -> Void
    ) {
        self.onPanelClose = onPanelClose
        self.onDeactivate = onDeactivate
        super.init()
        setupPanel(contentView: contentView)
        setupObservers()
    }

    func slideIn() {
        floatingPanel?.slideIn()
    }

    func slideOut() {
        floatingPanel?.slideOut()
    }

    func tearDown() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = deactivateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        screenObserver = nil
        deactivateObserver = nil
    }

    // MARK: - Private

    private func setupPanel(contentView: some View) {
        guard let screen = NSScreen.main else { return }

        let panel = FloatingPanel(contentRect: PanelConstants.frame(for: screen))
        panel.contentView = NSHostingView(rootView: contentView)
        panel.delegate = self
        floatingPanel = panel
    }

    private func setupObservers() {
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

        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDeactivate()
            }
        }
    }

    private func repositionPanel() {
        guard let screen = NSScreen.main, let panel = floatingPanel else { return }
        panel.setFrame(PanelConstants.frame(for: screen), display: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onPanelClose()
    }
}
