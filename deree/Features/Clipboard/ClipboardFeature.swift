import AppKit
import ComposableArchitecture
import Foundation
import os

@Reducer
struct ClipboardFeature {
    @ObservableState
    struct State: Equatable {
        var images: IdentifiedArrayOf<ClipboardImage> = []
        var thumbnails: [UUID: Data] = [:]
        var isPolling: Bool = false
        var lastChangeCount: Int = 0
        var lastError: FeatureError?
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
        case operationFailed(FeatureError)
    }

    @Dependency(\.clipboardClient) var clipboardClient
    @Dependency(\.storageClient) var storageClient
    @Dependency(\.continuousClock) var clock

    private static let logger = Logger(subsystem: "com.chigichan24.deree", category: "ClipboardFeature")

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
                            let thumbs = await loadThumbnails(for: images)
                            await send(.thumbnailsLoaded(thumbs))
                        } catch let error as StorageError {
                            await send(.operationFailed(.storageFailed(error)))
                        } catch {
                            await send(.operationFailed(.storageFailed(.invalidImageData)))
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
                        await loadThumbnail(for: result.saved.id, send: send)
                    } catch {
                        await send(.operationFailed(.storageFailed(error as? StorageError ?? .invalidImageData)))
                    }
                }

            case let .imagesLoaded(images):
                state.images = images
                state.thumbnails = [:]
                state.lastError = nil
                return .none

            case let .thumbnailsLoaded(thumbs):
                state.thumbnails = thumbs
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
                return .run { [id] _ in
                    do {
                        try await storageClient.delete(id)
                    } catch {
                        Self.logger.warning("Failed to delete image \(id) from storage: \(error)")
                    }
                }

            case let .copyImageToPasteboard(id):
                guard state.images[id: id] != nil else { return .none }
                return .run { [id] send in
                    do {
                        let fullData = try await storageClient.loadFull(id)
                        try await MainActor.run { try clipboardClient.writeImage(fullData) }
                        await send(.imageCopiedToPasteboard)
                    } catch let error as StorageError {
                        await send(.operationFailed(.storageFailed(error)))
                    } catch let error as ClipboardError {
                        await send(.operationFailed(.clipboardFailed(error)))
                    } catch {
                        await send(.operationFailed(.clipboardFailed(.invalidImageData)))
                    }
                }

            case .imageCopiedToPasteboard:
                state.lastChangeCount = clipboardClient.changeCount()
                return .none

            case let .operationFailed(error):
                state.lastError = error
                return .none
            }
        }
    }

    // MARK: - Thumbnail loading helpers

    private func loadThumbnails(
        for images: IdentifiedArrayOf<ClipboardImage>
    ) async -> [UUID: Data] {
        var thumbs: [UUID: Data] = [:]
        for image in images {
            do {
                let data = try await storageClient.loadThumbnail(image.id)
                thumbs[image.id] = data
            } catch {
                Self.logger.warning("Failed to load thumbnail for \(image.id): \(error)")
            }
        }
        return thumbs
    }

    private func loadThumbnail(
        for id: UUID,
        send: Send<Action>
    ) async {
        do {
            let data = try await storageClient.loadThumbnail(id)
            await send(.thumbnailLoaded(id, data))
        } catch {
            Self.logger.warning("Failed to load thumbnail for \(id): \(error)")
        }
    }
}
