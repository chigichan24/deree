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
        fullDirectory.appendingPathComponent("full_\(id).png")
    }

    private func thumbFileURL(for id: UUID) -> URL {
        thumbDirectory.appendingPathComponent("thumb_\(id).png")
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

        let id = UUID()
        let now = Date()
        let (width, height) = try parseImageDimensions(from: imageData)

        let fullURL = fullFileURL(for: id)
        let thumbURL = thumbFileURL(for: id)

        try imageData.write(to: fullURL)

        let thumbnailData: Data
        do {
            thumbnailData = try generateThumbnail(from: imageData, maxWidth: Self.thumbnailMaxWidth)
            try thumbnailData.write(to: thumbURL)
        } catch {
            try? FileManager.default.removeItem(at: fullURL)
            throw error
        }

        let image = ClipboardImage(
            id: id,
            createdAt: now,
            width: width,
            height: height
        )

        var images = try readMetadata()
        images.insert(image, at: 0)

        var evictedIDs: [UUID] = []
        while images.count > Self.maxImageCount {
            let removed = images.removeLast()
            do {
                try removeFilesStrict(for: removed.id)
            } catch {
                Self.logger.warning("Failed to remove evicted files for \(removed.id): \(error)")
            }
            evictedIDs.append(removed.id)
        }

        do {
            try writeMetadata(images)
        } catch {
            try? FileManager.default.removeItem(at: fullURL)
            try? FileManager.default.removeItem(at: thumbURL)
            throw error
        }

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

    // MARK: - Private helpers

    private static let maxImageCount = 50
    private static let thumbnailMaxWidth: CGFloat = 200

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
    }

    private func parseImageDimensions(from imageData: Data) throws -> (width: Int, height: Int) {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
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
        let decoder = JSONDecoder()
        return try decoder.decode([ClipboardImage].self, from: data)
    }

    private func writeMetadata(_ images: [ClipboardImage]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(images)
        try data.write(to: metadataURL)
    }

    private func removeFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: fullFileURL(for: id))
        try? FileManager.default.removeItem(at: thumbFileURL(for: id))
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

    private func generateThumbnail(from imageData: Data, maxWidth: CGFloat) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw StorageError.invalidImageData
        }

        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        guard originalWidth > 0, originalHeight > 0 else {
            throw StorageError.invalidImageData
        }

        let scale = originalWidth > maxWidth ? maxWidth / originalWidth : 1.0
        let newWidth = Int(round(originalWidth * scale))
        let newHeight = Int(round(originalHeight * scale))

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StorageError.thumbnailGenerationFailed
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let thumbnail = context.makeImage() else {
            throw StorageError.thumbnailGenerationFailed
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData, "public.png" as CFString, 1, nil
        ) else {
            throw StorageError.thumbnailGenerationFailed
        }

        CGImageDestinationAddImage(destination, thumbnail, nil)
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
