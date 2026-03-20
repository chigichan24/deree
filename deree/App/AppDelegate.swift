import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store(initialState: AppReducer.State()) {
        AppReducer()
    }

    private var floatingPanel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var screenObserver: (any NSObjectProtocol)?
    private var deactivateObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupFloatingPanel()
        store.send(.appDidFinishLaunching)

        _ = observe { [weak self] in
            guard let self else { return }
            let isVisible = store.panel.isPanelVisible
            updateStatusIcon(active: isVisible)
            if isVisible {
                floatingPanel?.slideIn()
            } else {
                floatingPanel?.slideOut {}
            }
        }
    }

    // MARK: - Status Item (Menu Bar Icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "photo.on.rectangle",
                accessibilityDescription: "deree"
            )
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        // Right-click menu for Quit
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit deree", action: #selector(quitApp), keyEquivalent: "q")
        statusItem?.menu = nil // Left-click triggers action, not menu
    }

    @objc private func statusItemClicked() {
        store.send(.menuBarToggleTapped)
    }

    @objc private func quitApp() {
        store.send(.quitButtonTapped)
    }

    private func updateStatusIcon(active: Bool) {
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: active ? "photo.on.rectangle.fill" : "photo.on.rectangle",
                accessibilityDescription: "deree"
            )
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

        // Reposition on screen change
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
