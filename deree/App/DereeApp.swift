import SwiftUI

@main
struct DereeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("deree", systemImage: "photo.on.rectangle") {
            MenuBarView(store: appDelegate.store)
        }
    }
}
