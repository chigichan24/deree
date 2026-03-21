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
        case clipboardChanged(changeCount: Int, imageData: Data)
        case imagesLoaded(IdentifiedArrayOf<ClipboardImage>)
        case thumbnailsLoaded([UUID: Data])
        case imageSaved(SaveResult)
        case thumbnailLoaded(UUID, Data)
        case imageDeleted(ClipboardImage.ID)
        case copyImageToPasteboard(ClipboardImage.ID)
        case imageCopiedToPasteboard(changeCount: Int)
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
                // Initial load and polling run independently via .merge:
                // if loadAll fails, polling still starts so new clipboard
                // images are captured even when history can't be restored.
                return .merge(
                    .run { send in
                        do {
                            let initialCount = await clipboardClient.changeCount()
                            await send(.imageCopiedToPasteboard(changeCount: initialCount))
                            let images = try await storageClient.loadAll()
                            await send(.imagesLoaded(images))
                            let thumbs = await loadThumbnails(for: images)
                            await send(.thumbnailsLoaded(thumbs))
                        } catch let error as StorageError {
                            await send(.operationFailed(.storageFailed(error)))
                        } catch {
                            await send(.operationFailed(.unexpectedError(error.localizedDescription)))
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
                let lastCount = state.lastChangeCount
                return .run { send in
                    let currentCount = await clipboardClient.changeCount()
                    guard currentCount != lastCount else { return }

                    guard let imageData = await clipboardClient.readImage() else {
                        // changeCount changed but no image (text copy, etc.)
                        await send(.clipboardChanged(changeCount: currentCount, imageData: Data()))
                        return
                    }

                    await send(.clipboardChanged(changeCount: currentCount, imageData: imageData))
                }

            case let .clipboardChanged(changeCount, imageData):
                state.lastChangeCount = changeCount
                guard !imageData.isEmpty else { return .none }

                return .run { send in
                    do {
                        let result = try await storageClient.save(imageData)
                        await send(.imageSaved(result))
                        await loadThumbnail(for: result.saved.id, send: send)
                    } catch let error as StorageError {
                        await send(.operationFailed(.storageFailed(error)))
                    } catch {
                        await send(.operationFailed(.unexpectedError(error.localizedDescription)))
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
                // Optimistic deletion: state is updated immediately, storage
                // deletion is best-effort. Orphan files from failed deletions
                // are acceptable for this app's scale (max 50 images).
                return .run { [id] _ in
                    do {
                        try await storageClient.delete(id)
                    } catch {
                        Self.logger.warning("Failed to delete image \(id) from storage: \(error)")
                    }
                }

            case let .copyImageToPasteboard(id):
                // Quick bail-out for IDs not in current state; storage-level
                // not-found is still handled in the catch below for race cases.
                guard state.images[id: id] != nil else { return .none }
                return .run { [id] send in
                    do {
                        let fullData = try await storageClient.loadFull(id)
                        try await clipboardClient.writeImage(fullData)
                        let newCount = await clipboardClient.changeCount()
                        await send(.imageCopiedToPasteboard(changeCount: newCount))
                    } catch let error as StorageError {
                        await send(.operationFailed(.storageFailed(error)))
                    } catch let error as ClipboardError {
                        await send(.operationFailed(.clipboardFailed(error)))
                    } catch {
                        await send(.operationFailed(.unexpectedError(error.localizedDescription)))
                    }
                }

            case let .imageCopiedToPasteboard(changeCount):
                state.lastChangeCount = changeCount
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
        await withTaskGroup(of: (UUID, Data?).self) { group in
            for image in images {
                group.addTask { [storageClient] in
                    do {
                        let data = try await storageClient.loadThumbnail(image.id)
                        return (image.id, data)
                    } catch {
                        Self.logger.warning("Failed to load thumbnail for \(image.id): \(error)")
                        return (image.id, nil)
                    }
                }
            }
            var thumbs: [UUID: Data] = [:]
            for await (id, data) in group {
                if let data { thumbs[id] = data }
            }
            return thumbs
        }
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
