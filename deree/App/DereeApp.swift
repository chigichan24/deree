import SwiftUI

@main
struct DereeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("deree", systemImage: "photo.on.rectangle") {
            Button(appDelegate.store.panel.isPanelVisible ? "Hide Panel" : "Show Panel") {
                appDelegate.store.send(.menuBarToggleTapped)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("Quit deree") {
                appDelegate.store.send(.quitButtonTapped)
            }
            .keyboardShortcut("q")
        }
    }
}
