import AppKit
import Dependencies
import Foundation
import IdentifiedCollections

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

private final class LiveStorage: Sendable {
    let baseDirectory: URL
    private var fullDirectory: URL { baseDirectory.appendingPathComponent("full") }
    private var thumbDirectory: URL { baseDirectory.appendingPathComponent("thumb") }
    private var metadataURL: URL { baseDirectory.appendingPathComponent("metadata.json") }

    init(baseDirectory: URL) {
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

    @StorageActor
    func loadAll() throws -> IdentifiedArrayOf<ClipboardImage> {
        let images = try readMetadata()
        return IdentifiedArrayOf(uniqueElements: images)
    }

    @StorageActor
    func loadFull(id: UUID) throws -> Data {
        let url = fullFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.imageNotFound(id)
        }
        return try Data(contentsOf: url)
    }

    @StorageActor
    func loadThumbnail(id: UUID) throws -> Data {
        let url = thumbFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.imageNotFound(id)
        }
        return try Data(contentsOf: url)
    }

    @StorageActor
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
            thumbnailData = try generateThumbnail(from: imageData, maxWidth: 200)
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

        var images: [ClipboardImage]
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            images = try readMetadata()
        } else {
            images = []
        }
        images.insert(image, at: 0)

        var evictedIDs: [UUID] = []
        while images.count > Self.maxImageCount {
            let removed = images.removeLast()
            removeFiles(for: removed.id)
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

    @StorageActor
    func delete(id: UUID) throws {
        var images = try readMetadata()
        guard let index = images.firstIndex(where: { $0.id == id }) else {
            throw StorageError.imageNotFound(id)
        }
        images.remove(at: index)
        try removeFilesStrict(for: id)
        try writeMetadata(images)
    }

    // MARK: - Private helpers

    private static let maxImageCount = 50

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
        guard let image = NSImage(data: imageData) else {
            throw StorageError.invalidImageData
        }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else {
            throw StorageError.invalidImageData
        }

        let scale: CGFloat
        if originalSize.width > maxWidth {
            scale = maxWidth / originalSize.width
        } else {
            scale = 1.0
        }

        let newSize = NSSize(
            width: round(originalSize.width * scale),
            height: round(originalSize.height * scale)
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            throw StorageError.thumbnailGenerationFailed
        }

        return pngData
    }
}

// MARK: - Errors

enum StorageError: Error, Equatable {
    case invalidImageData
    case imageNotFound(UUID)
    case thumbnailGenerationFailed
}
