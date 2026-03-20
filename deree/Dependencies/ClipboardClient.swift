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
    var writeImage: @Sendable (Data) throws -> Void
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
                guard let objects = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                ),
                    let image = objects.first as? NSImage,
                    let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(
                        using: .png,
                        properties: [:]
                    )
                else {
                    return nil
                }
                return pngData
            }
        },
        writeImage: { data in
            try MainActor.assumeIsolated {
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
