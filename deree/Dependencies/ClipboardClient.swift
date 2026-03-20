import AppKit
import Dependencies
import DependenciesMacros

enum ClipboardError: Error, Equatable {
    case invalidImageData
}

@DependencyClient
struct ClipboardClient: Sendable {
    var changeCount: @Sendable () -> Int = { 0 }
    var readImage: @Sendable () -> Data? = { nil }
    var writeImage: @Sendable (Data) async throws -> Void
}

extension ClipboardClient: DependencyKey {
    static let liveValue = ClipboardClient(
        changeCount: {
            MainActor.assumeIsolated {
                NSPasteboard.general.changeCount
            }
        },
        readImage: {
            MainActor.assumeIsolated {
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
                    let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(using: .png, properties: [:])
                {
                    return pngData
                }

                // Fall back to direct image data (screenshots, copy from apps)
                if let objects = pasteboard.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                ),
                    let image = objects.first as? NSImage,
                    let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(using: .png, properties: [:])
                {
                    return pngData
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
