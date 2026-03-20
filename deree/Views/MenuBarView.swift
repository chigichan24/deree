import ComposableArchitecture
import SwiftUI

struct MenuBarView: View {
    let store: StoreOf<AppReducer>

    var body: some View {
        Button {
            store.send(.menuBarToggleTapped)
        } label: {
            Label(
                store.panel.isPanelVisible ? "Hide Panel" : "Show Panel",
                systemImage: store.panel.isPanelVisible
                    ? "sidebar.right"
                    : "sidebar.left"
            )
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Divider()

        Button {
            store.send(.quitButtonTapped)
        } label: {
            Label("Quit", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

#Preview {
    MenuBarView(
        store: Store(
            initialState: AppReducer.State()
        ) {
            AppReducer()
        }
    )
}
