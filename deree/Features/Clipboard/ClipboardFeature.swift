import ComposableArchitecture
import Foundation

@Reducer
struct ClipboardFeature {
    @ObservableState
    struct State: Equatable {
        var images: IdentifiedArrayOf<ClipboardImage> = []
        var isPolling: Bool = false
        var lastChangeCount: Int = 0
    }

    enum Action: Equatable {
        case startPolling
        case stopPolling
        case timerTicked
        case imagesLoaded(IdentifiedArrayOf<ClipboardImage>)
        case imageSaved(SaveResult)
        case imageDeleted(ClipboardImage.ID)
        case copyImageToPasteboard(ClipboardImage.ID)
        case imageCopiedToPasteboard
    }

    @Dependency(\.clipboardClient) var clipboardClient
    @Dependency(\.storageClient) var storageClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case polling }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startPolling:
                state.isPolling = true
                state.lastChangeCount = clipboardClient.changeCount()
                return .merge(
                    .run { send in
                        let images = try await storageClient.loadAll()
                        await send(.imagesLoaded(images))
                    },
                    .run { send in
                        for await _ in clock.timer(interval: .milliseconds(500)) {
                            await send(.timerTicked)
                        }
                    }
                    .cancellable(id: CancelID.polling)
                )

            case .stopPolling:
                state.isPolling = false
                return .cancel(id: CancelID.polling)

            case .timerTicked:
                let currentCount = clipboardClient.changeCount()
                guard currentCount != state.lastChangeCount else {
                    return .none
                }
                state.lastChangeCount = currentCount

                let imageData = clipboardClient.readImage()
                guard let imageData else {
                    return .none
                }

                return .run { send in
                    let result = try await storageClient.save(imageData)
                    await send(.imageSaved(result))
                }

            case let .imagesLoaded(images):
                state.images = images
                return .none

            case let .imageSaved(result):
                state.images.insert(result.saved, at: 0)
                for id in result.evictedIDs {
                    state.images.remove(id: id)
                }
                return .none

            case let .imageDeleted(id):
                state.images.remove(id: id)
                return .none

            case let .copyImageToPasteboard(id):
                guard state.images[id: id] != nil else { return .none }
                return .run { [id] send in
                    let fullData = try await storageClient.loadFull(id)
                    clipboardClient.writeImage(fullData)
                    await send(.imageCopiedToPasteboard)
                }

            case .imageCopiedToPasteboard:
                state.lastChangeCount = clipboardClient.changeCount()
                return .none
            }
        }
    }
}
