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
    private static let maxImageCount = 50

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

    @StorageActor
    func loadAll() throws -> IdentifiedArrayOf<ClipboardImage> {
        let images = try readMetadata()
        return IdentifiedArrayOf(uniqueElements: images)
    }

    @StorageActor
    func loadFull(id: UUID) throws -> Data {
        let image = try findImage(id: id)
        let url = fullDirectory.appendingPathComponent(image.fullFileName)
        return try Data(contentsOf: url)
    }

    @StorageActor
    func loadThumbnail(id: UUID) throws -> Data {
        let image = try findImage(id: id)
        let url = thumbDirectory.appendingPathComponent(image.thumbnailFileName)
        return try Data(contentsOf: url)
    }

    @StorageActor
    func save(imageData: Data) throws -> ClipboardImage {
        try ensureDirectories()

        let id = UUID()
        let now = Date()

        // Parse image dimensions
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw StorageError.invalidImageData
        }

        let fullFileName = "full_\(id).png"
        let thumbFileName = "thumb_\(id).png"

        // Save full image
        let fullURL = fullDirectory.appendingPathComponent(fullFileName)
        try imageData.write(to: fullURL)

        // Generate and save thumbnail
        let thumbnailData = try generateThumbnail(from: imageData, maxWidth: 200)
        let thumbURL = thumbDirectory.appendingPathComponent(thumbFileName)
        try thumbnailData.write(to: thumbURL)

        let image = ClipboardImage(
            id: id,
            createdAt: now,
            thumbnailFileName: thumbFileName,
            fullFileName: fullFileName,
            width: width,
            height: height
        )

        // Update metadata
        var images: [ClipboardImage]
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            images = try readMetadata()
        } else {
            images = []
        }
        images.insert(image, at: 0)

        // Enforce cap
        while images.count > Self.maxImageCount {
            let removed = images.removeLast()
            removeFiles(for: removed)
        }

        try writeMetadata(images)

        return image
    }

    @StorageActor
    func delete(id: UUID) throws {
        var images = try readMetadata()
        guard let index = images.firstIndex(where: { $0.id == id }) else {
            throw StorageError.imageNotFound(id)
        }
        let image = images[index]
        removeFiles(for: image)
        images.remove(at: index)
        try writeMetadata(images)
    }

    // MARK: - Private helpers

    private static let maxImageCount = 50

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
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

    private func findImage(id: UUID) throws -> ClipboardImage {
        let images = try readMetadata()
        guard let image = images.first(where: { $0.id == id }) else {
            throw StorageError.imageNotFound(id)
        }
        return image
    }

    private func removeFiles(for image: ClipboardImage) {
        let fullURL = fullDirectory.appendingPathComponent(image.fullFileName)
        let thumbURL = thumbDirectory.appendingPathComponent(image.thumbnailFileName)
        try? FileManager.default.removeItem(at: fullURL)
        try? FileManager.default.removeItem(at: thumbURL)
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
