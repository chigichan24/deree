import Dependencies
import DependenciesMacros
import Foundation
import IdentifiedCollections

struct SaveResult: Equatable, Sendable {
    let saved: ClipboardImage
    let evictedIDs: [UUID]
}

@DependencyClient
struct StorageClient: Sendable {
    var loadAll: @Sendable () async throws -> IdentifiedArrayOf<ClipboardImage>
    var loadFull: @Sendable (_ id: UUID) async throws -> Data
    var loadThumbnail: @Sendable (_ id: UUID) async throws -> Data
    var save: @Sendable (_ imageData: Data) async throws -> SaveResult
    var delete: @Sendable (_ id: UUID) async throws -> Void
}

extension StorageClient: TestDependencyKey {
    static let testValue = StorageClient()
}

extension DependencyValues {
    var storageClient: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}
