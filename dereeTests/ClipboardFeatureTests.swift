import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import deree

@MainActor
struct ClipboardFeatureTests {
    @Test func startPolling_loadsImagesAndSetsPollingTrue() async {
        let mockImages: IdentifiedArrayOf<ClipboardImage> = [
            ClipboardImage(
                id: UUID(0),
                createdAt: Date(timeIntervalSince1970: 200),

                width: 100,
                height: 100
            ),
        ]

        let store = TestStore(initialState: ClipboardFeature.State()) {
            ClipboardFeature()
        } withDependencies: {
            $0.clipboardClient.changeCount = { 5 }
            $0.storageClient.loadAll = { mockImages }
            $0.storageClient.loadThumbnail = { _ in Data() }
            $0.continuousClock = ImmediateClock()
        }

        store.exhaustivity = .off

        await store.send(.startPolling) {
            $0.isPolling = true
            $0.lastChangeCount = 5
        }

        await store.receive(\.imagesLoaded) {
            $0.images = mockImages
        }
    }

    @Test func stopPolling_cancelsTimer() async {
        let store = TestStore(
            initialState: ClipboardFeature.State(isPolling: true)
        ) {
            ClipboardFeature()
        }

        await store.send(.stopPolling) {
            $0.isPolling = false
        }
    }

    @Test func timerTick_noChange_doesNothing() async {
        let store = TestStore(
            initialState: ClipboardFeature.State(
                isPolling: true,
                lastChangeCount: 5
            )
        ) {
            ClipboardFeature()
        } withDependencies: {
            $0.clipboardClient.changeCount = { 5 }
        }

        await store.send(.timerTicked)
    }

    @Test func timerTick_withChange_capturesImage() async {
        let savedImage = ClipboardImage(
            id: UUID(0),
            createdAt: Date(),
            width: 200,
            height: 150
        )
        let testImageData = Data([0x89, 0x50, 0x4E, 0x47])

        let store = TestStore(
            initialState: ClipboardFeature.State(
                isPolling: true,
                lastChangeCount: 5
            )
        ) {
            ClipboardFeature()
        } withDependencies: {
            $0.clipboardClient.changeCount = { 6 }
            $0.clipboardClient.readImage = { testImageData }
            $0.storageClient.save = { _ in SaveResult(saved: savedImage, evictedIDs: []) }
            $0.storageClient.loadThumbnail = { _ in Data() }
        }

        store.exhaustivity = .off

        await store.send(.timerTicked) {
            $0.lastChangeCount = 6
        }

        await store.receive(\.imageSaved) {
            $0.images = [savedImage]
        }
    }

    @Test func timerTick_withChange_noImage_doesNothing() async {
        let store = TestStore(
            initialState: ClipboardFeature.State(
                isPolling: true,
                lastChangeCount: 5
            )
        ) {
            ClipboardFeature()
        } withDependencies: {
            $0.clipboardClient.changeCount = { 6 }
            $0.clipboardClient.readImage = { nil }
        }

        await store.send(.timerTicked) {
            $0.lastChangeCount = 6
        }
    }

    @Test func imageSaved_withEvictions_removesFromState() async {
        var existingImages = IdentifiedArrayOf<ClipboardImage>()
        for i in 0..<50 {
            existingImages.append(
                ClipboardImage(
                    id: UUID(i),
                    createdAt: Date(timeIntervalSince1970: Double(1000 - i)),

                    width: 100,
                    height: 100
                )
            )
        }

        let newImage = ClipboardImage(
            id: UUID(99),
            createdAt: Date(timeIntervalSince1970: 2000),

            width: 200,
            height: 150
        )

        let oldestId = existingImages.last!.id
        let result = SaveResult(saved: newImage, evictedIDs: [oldestId])

        let store = TestStore(
            initialState: ClipboardFeature.State(images: existingImages)
        ) {
            ClipboardFeature()
        }

        await store.send(.imageSaved(result)) {
            $0.images.insert(newImage, at: 0)
            $0.images.remove(id: oldestId)
        }
    }

    @Test func copyImageToPasteboard_writesAndUpdatesChangeCount() async {
        let image = ClipboardImage(
            id: UUID(0),
            createdAt: Date(),
            width: 100,
            height: 100
        )
        let fullData = Data([0x89, 0x50, 0x4E, 0x47])
        let writtenData = LockIsolated<Data?>(nil)

        let store = TestStore(
            initialState: ClipboardFeature.State(
                images: [image],
                lastChangeCount: 5
            )
        ) {
            ClipboardFeature()
        } withDependencies: {
            $0.storageClient.loadFull = { _ in fullData }
            $0.clipboardClient.writeImage = { data in
                writtenData.setValue(data)
            }
            $0.clipboardClient.changeCount = { 10 }
        }

        await store.send(.copyImageToPasteboard(image.id))

        await store.receive(\.imageCopiedToPasteboard) {
            $0.lastChangeCount = 10
        }

        #expect(writtenData.value == fullData)
    }

    @Test func imagesLoaded_setsImages() async {
        let images: IdentifiedArrayOf<ClipboardImage> = [
            ClipboardImage(
                id: UUID(0),
                createdAt: Date(),

                width: 100,
                height: 100
            ),
        ]

        let store = TestStore(initialState: ClipboardFeature.State()) {
            ClipboardFeature()
        }

        await store.send(.imagesLoaded(images)) {
            $0.images = images
            $0.thumbnails = [:]
        }
    }

    @Test func timerTick_saveFails_setsLastError() async {
        let store = TestStore(
            initialState: ClipboardFeature.State(
                isPolling: true,
                lastChangeCount: 5
            )
        ) {
            ClipboardFeature()
        } withDependencies: {
            $0.clipboardClient.changeCount = { 6 }
            $0.clipboardClient.readImage = { Data([0x89]) }
            $0.storageClient.save = { _ in throw StorageError.invalidImageData }
        }

        await store.send(.timerTicked) {
            $0.lastChangeCount = 6
        }

        await store.receive(\.operationFailed) {
            $0.lastError = .storageFailed(
                StorageError.invalidImageData.localizedDescription
            )
        }
    }

    @Test func copyImage_loadFullFails_setsLastError() async {
        let image = ClipboardImage(
            id: UUID(0),
            createdAt: Date(),
            width: 100,
            height: 100
        )
        let store = TestStore(
            initialState: ClipboardFeature.State(images: [image])
        ) {
            ClipboardFeature()
        } withDependencies: {
            $0.storageClient.loadFull = { id in throw StorageError.imageNotFound(id) }
        }

        await store.send(.copyImageToPasteboard(image.id))

        await store.receive(\.operationFailed) {
            $0.lastError = .clipboardFailed(
                StorageError.imageNotFound(UUID(0)).localizedDescription
            )
        }
    }
}
