import ComposableArchitecture
import Testing

@testable import deree

@MainActor
struct AppReducerTests {
    @Test func appDidFinishLaunching_startsPolling() async {
        let store = TestStore(initialState: AppReducer.State()) {
            AppReducer()
        } withDependencies: {
            $0.clipboardClient.changeCount = { 0 }
            $0.storageClient.loadAll = { [] }
            $0.continuousClock = ImmediateClock()
        }

        store.exhaustivity = .off

        await store.send(.appDidFinishLaunching)

        await store.receive(\.clipboard.startPolling)
    }

    @Test func menuBarToggleTapped_togglesPanel() async {
        let store = TestStore(initialState: AppReducer.State()) {
            AppReducer()
        }

        store.exhaustivity = .off

        await store.send(.menuBarToggleTapped)

        await store.receive(\.panel.togglePanel)
    }
}
