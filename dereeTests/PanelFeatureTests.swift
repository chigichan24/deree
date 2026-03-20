import ComposableArchitecture
import Testing

@testable import deree

@MainActor
struct PanelFeatureTests {
    @Test func togglePanel_flipsVisibility() async {
        let store = TestStore(initialState: PanelFeature.State()) {
            PanelFeature()
        }

        await store.send(.togglePanel) {
            $0.isPanelVisible = true
        }

        await store.send(.togglePanel) {
            $0.isPanelVisible = false
        }
    }

    @Test func showPanel_setsTrue() async {
        let store = TestStore(initialState: PanelFeature.State()) {
            PanelFeature()
        }

        await store.send(.showPanel) {
            $0.isPanelVisible = true
        }
    }

    @Test func hidePanel_setsFalse() async {
        let store = TestStore(
            initialState: PanelFeature.State(isPanelVisible: true)
        ) {
            PanelFeature()
        }

        await store.send(.hidePanel) {
            $0.isPanelVisible = false
        }
    }
}
