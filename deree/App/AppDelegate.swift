import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store(initialState: AppReducer.State()) {
        AppReducer()
    }

    private var statusItemController: StatusItemController?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            onLeftClick: { [weak self] in
                self?.store.send(.menuBarToggleTapped)
            },
            onQuit: { [weak self] in
                self?.store.send(.quitButtonTapped)
            }
        )

        panelController = PanelController(
            contentView: ClipboardImageListView(
                store: store.scope(state: \.clipboard, action: \.clipboard)
            ),
            onPanelClose: { [weak self] in
                self?.store.send(.panel(.hidePanel))
            },
            onDeactivate: { [weak self] in
                _ = self?.store.send(.panel(.hidePanel))
            }
        )

        store.send(.appDidFinishLaunching)

        _ = observe { [weak self] in
            guard let self else { return }
            let isVisible = store.panel.isPanelVisible
            statusItemController?.updateIcon(active: isVisible)
            if isVisible {
                panelController?.slideIn()
            } else {
                panelController?.slideOut()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.tearDown()
    }
}
