import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct ClipboardFeature {
    @ObservableState
    struct State: Equatable {
        var images: IdentifiedArrayOf<ClipboardImage> = []
        var thumbnails: [UUID: Data] = [:]
        var isPolling: Bool = false
        var lastChangeCount: Int = 0
        var lastError: String?
    }

    enum Action: Equatable {
        case startPolling
        case stopPolling
        case timerTicked
        case imagesLoaded(IdentifiedArrayOf<ClipboardImage>)
        case thumbnailsLoaded([UUID: Data])
        case imageSaved(SaveResult)
        case thumbnailLoaded(UUID, Data)
        case imageDeleted(ClipboardImage.ID)
        case copyImageToPasteboard(ClipboardImage.ID)
        case imageCopiedToPasteboard
        case operationFailed(String)
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
                        do {
                            let images = try await storageClient.loadAll()
                            await send(.imagesLoaded(images))
                            var thumbs: [UUID: Data] = [:]
                            for image in images {
                                if let data = try? await storageClient.loadThumbnail(image.id) {
                                    thumbs[image.id] = data
                                }
                            }
                            await send(.thumbnailsLoaded(thumbs))
                        } catch {
                            await send(.operationFailed(error.localizedDescription))
                        }
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
                    do {
                        let result = try await storageClient.save(imageData)
                        await send(.imageSaved(result))
                        if let thumbData = try? await storageClient.loadThumbnail(result.saved.id) {
                            await send(.thumbnailLoaded(result.saved.id, thumbData))
                        }
                    } catch {
                        await send(.operationFailed(error.localizedDescription))
                    }
                }

            case let .imagesLoaded(images):
                state.images = images
                state.lastError = nil
                return .none

            case let .thumbnailsLoaded(thumbs):
                state.thumbnails.merge(thumbs) { _, new in new }
                return .none

            case let .imageSaved(result):
                state.images.insert(result.saved, at: 0)
                for id in result.evictedIDs {
                    state.images.remove(id: id)
                    state.thumbnails.removeValue(forKey: id)
                }
                state.lastError = nil
                return .none

            case let .thumbnailLoaded(id, data):
                state.thumbnails[id] = data
                return .none

            case let .imageDeleted(id):
                state.images.remove(id: id)
                state.thumbnails.removeValue(forKey: id)
                return .none

            case let .copyImageToPasteboard(id):
                guard state.images[id: id] != nil else { return .none }
                return .run { [id] send in
                    do {
                        let fullData = try await storageClient.loadFull(id)
                        await MainActor.run { clipboardClient.writeImage(fullData) }
                        await send(.imageCopiedToPasteboard)
                    } catch {
                        await send(.operationFailed(error.localizedDescription))
                    }
                }

            case .imageCopiedToPasteboard:
                state.lastChangeCount = clipboardClient.changeCount()
                return .none

            case let .operationFailed(message):
                state.lastError = message
                return .none
            }
        }
    }
}
