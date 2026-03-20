import AppKit
import ComposableArchitecture

@Reducer
struct AppReducer {
    @ObservableState
    struct State: Equatable {
        var clipboard = ClipboardFeature.State()
        var panel = PanelFeature.State()
    }

    enum Action: Equatable {
        case clipboard(ClipboardFeature.Action)
        case panel(PanelFeature.Action)
        case appDidFinishLaunching
        case quitButtonTapped
        case menuBarToggleTapped
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.clipboard, action: \.clipboard) {
            ClipboardFeature()
        }
        Scope(state: \.panel, action: \.panel) {
            PanelFeature()
        }
        Reduce { _, action in
            switch action {
            case .appDidFinishLaunching:
                return .send(.clipboard(.startPolling))

            case .menuBarToggleTapped:
                return .send(.panel(.togglePanel))

            case .quitButtonTapped:
                return .run { _ in
                    await NSApplication.shared.terminate(nil)
                }

            case .clipboard, .panel:
                return .none
            }
        }
    }
}
