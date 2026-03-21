import AppKit
import Dependencies
import DependenciesMacros

enum ClipboardError: Error, Equatable {
    case invalidImageData
}

@DependencyClient
struct ClipboardClient: Sendable {
    var changeCount: @Sendable () async -> Int = { 0 }
    var readImage: @Sendable () async -> Data? = { nil }
    var writeImage: @Sendable (Data) async throws -> Void
}

extension ClipboardClient: DependencyKey {
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static let liveValue = ClipboardClient(
        changeCount: {
            await MainActor.run {
                NSPasteboard.general.changeCount
            }
        },
        readImage: {
            await MainActor.run {
                let pasteboard = NSPasteboard.general

                // Try file URLs first (Cmd+C in Finder gives file URL + icon;
                // we want the actual file content, not the Finder icon)
                if let urls = pasteboard.readObjects(
                    forClasses: [NSURL.self],
                    options: [
                        .urlReadingFileURLsOnly: true,
                        .urlReadingContentsConformToTypes: NSImage.imageTypes,
                    ]
                ) as? [URL],
                    let url = urls.first,
                    let image = NSImage(contentsOf: url),
                    let data = pngData(from: image)
                {
                    return data
                }

                // Fall back to direct image data (screenshots, copy from apps)
                if let objects = pasteboard.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                ),
                    let image = objects.first as? NSImage,
                    let data = pngData(from: image)
                {
                    return data
                }

                return nil
            }
        },
        writeImage: { data in
            try await MainActor.run {
                guard let image = NSImage(data: data) else {
                    throw ClipboardError.invalidImageData
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            }
        }
    )
}

extension ClipboardClient: TestDependencyKey {
    static let testValue = ClipboardClient()
}

extension DependencyValues {
    var clipboardClient: ClipboardClient {
        get { self[ClipboardClient.self] }
        set { self[ClipboardClient.self] = newValue }
    }
}
