import ComposableArchitecture

@Reducer
struct PanelFeature {
    @ObservableState
    struct State: Equatable {
        var isPanelVisible: Bool = false
    }

    enum Action: Equatable {
        case togglePanel
        case showPanel
        case hidePanel
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .togglePanel:
                state.isPanelVisible.toggle()
                return .none
            case .showPanel:
                state.isPanelVisible = true
                return .none
            case .hidePanel:
                state.isPanelVisible = false
                return .none
            }
        }
    }
}
