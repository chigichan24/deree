import CoreGraphics
import Dependencies
import Foundation
import IdentifiedCollections
import ImageIO
import os

// MARK: - StorageActor

@globalActor
actor StorageActor: GlobalActor {
    static let shared = StorageActor()
}

// MARK: - Storage Constants

enum StorageConstants {
    static let maxImageCount = 50
    static let thumbnailMaxWidth: CGFloat = 200
}

// MARK: - Live Implementation

extension StorageClient {
    static func makeLive(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("deree")
    ) -> StorageClient {
        let storage = LiveStorage(baseDirectory: baseDirectory)

        return StorageClient(
            loadAll: { try await storage.loadAll() },
            loadFull: { id in try await storage.loadFull(id: id) },
            loadThumbnail: { id in try await storage.loadThumbnail(id: id) },
            save: { data in try await storage.save(imageData: data) },
            delete: { id in try await storage.delete(id: id) }
        )
    }
}

// MARK: - DependencyKey conformance

extension StorageClient: DependencyKey {
    static let liveValue: StorageClient = .makeLive()
}

// MARK: - LiveStorage

@StorageActor
private final class LiveStorage: Sendable {
    private static let logger = Logger(subsystem: "com.chigichan24.deree", category: "LiveStorage")

    let baseDirectory: URL
    private var fullDirectory: URL { baseDirectory.appendingPathComponent("full") }
    private var thumbDirectory: URL { baseDirectory.appendingPathComponent("thumb") }
    private var metadataURL: URL { baseDirectory.appendingPathComponent("metadata.json") }

    nonisolated init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - File URL helpers

    private func fullFileURL(for id: UUID) -> URL {
        fullDirectory.appendingPathComponent(ClipboardImage.fullFileName(for: id))
    }

    private func thumbFileURL(for id: UUID) -> URL {
        thumbDirectory.appendingPathComponent(ClipboardImage.thumbFileName(for: id))
    }

    // MARK: - Public API

    func loadAll() throws -> IdentifiedArrayOf<ClipboardImage> {
        let images = try readMetadata()
        return IdentifiedArrayOf(uniqueElements: images)
    }

    func loadFull(id: UUID) throws -> Data {
        let url = fullFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.imageNotFound(id)
        }
        return try Data(contentsOf: url)
    }

    func loadThumbnail(id: UUID) throws -> Data {
        let url = thumbFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.imageNotFound(id)
        }
        return try Data(contentsOf: url)
    }

    func save(imageData: Data) throws -> SaveResult {
        try ensureDirectories()

        let source = try createImageSource(from: imageData)
        let id = UUID()
        let (width, height) = try imageDimensions(from: source)

        do {
            try writeFullImage(imageData, for: id)
            try writeThumbnail(from: source, for: id)
        } catch {
            cleanupFiles(for: id)
            throw error
        }

        let image = ClipboardImage(id: id, createdAt: Date(), width: width, height: height)
        let evictedIDs = try updateMetadataInserting(image, cleanupID: id)

        return SaveResult(saved: image, evictedIDs: evictedIDs)
    }

    func delete(id: UUID) throws {
        var images = try readMetadata()
        guard let index = images.firstIndex(where: { $0.id == id }) else {
            throw StorageError.imageNotFound(id)
        }
        images.remove(at: index)
        try writeMetadata(images)
        do {
            try removeFilesStrict(for: id)
        } catch {
            Self.logger.warning("Failed to remove files for deleted image \(id): \(error)")
        }
    }

    // MARK: - Save sub-steps

    private func writeFullImage(_ imageData: Data, for id: UUID) throws {
        try imageData.write(to: fullFileURL(for: id))
    }

    private func writeThumbnail(from source: CGImageSource, for id: UUID) throws {
        let thumbnailData = try generateThumbnail(from: source, maxWidth: StorageConstants.thumbnailMaxWidth)
        try thumbnailData.write(to: thumbFileURL(for: id))
    }

    private func updateMetadataInserting(_ image: ClipboardImage, cleanupID: UUID) throws -> Set<UUID> {
        var images = try readMetadata()
        images.insert(image, at: 0)
        let evictedIDs = evictExcessImages(from: &images)

        do {
            try writeMetadata(images)
        } catch {
            cleanupFiles(for: cleanupID)
            throw error
        }

        return evictedIDs
    }

    private func cleanupFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: fullFileURL(for: id))
        try? FileManager.default.removeItem(at: thumbFileURL(for: id))
    }

    // MARK: - Private helpers

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
    }

    private func evictExcessImages(from images: inout [ClipboardImage]) -> Set<UUID> {
        var evictedIDs = Set<UUID>()
        while images.count > StorageConstants.maxImageCount {
            let removed = images.removeLast()
            do {
                try removeFilesStrict(for: removed.id)
            } catch {
                Self.logger.warning("Failed to remove evicted files for \(removed.id): \(error)")
            }
            evictedIDs.insert(removed.id)
        }
        return evictedIDs
    }

    private func createImageSource(from imageData: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw StorageError.invalidImageData
        }
        return source
    }

    private func imageDimensions(from source: CGImageSource) throws -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw StorageError.invalidImageData
        }
        return (width, height)
    }

    private func readMetadata() throws -> [ClipboardImage] {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return []
        }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([ClipboardImage].self, from: data)
    }

    private func writeMetadata(_ images: [ClipboardImage]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(images).write(to: metadataURL)
    }

    private func removeFilesStrict(for id: UUID) throws {
        let fullURL = fullFileURL(for: id)
        let thumbURL = thumbFileURL(for: id)
        if FileManager.default.fileExists(atPath: fullURL.path) {
            try FileManager.default.removeItem(at: fullURL)
        }
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            try FileManager.default.removeItem(at: thumbURL)
        }
    }

    private func generateThumbnail(from source: CGImageSource, maxWidth: CGFloat) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxWidth),
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StorageError.thumbnailGenerationFailed
        }

        return try encodePNG(from: thumbnail)
    }

    private func encodePNG(from cgImage: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData, "public.png" as CFString, 1, nil
        ) else {
            throw StorageError.thumbnailGenerationFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StorageError.thumbnailGenerationFailed
        }
        return mutableData as Data
    }
}

// MARK: - Errors

enum StorageError: Error, Equatable {
    case invalidImageData
    case imageNotFound(UUID)
    case thumbnailGenerationFailed
}
