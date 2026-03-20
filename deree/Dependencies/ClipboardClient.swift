import AppKit
import Dependencies
import DependenciesMacros

@DependencyClient
struct ClipboardClient: Sendable {
    var changeCount: @Sendable () -> Int = { 0 }
    var readImage: @Sendable () -> Data? = { nil }
    var writeImage: @Sendable (Data) -> Void
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
            MainActor.assumeIsolated {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if let image = NSImage(data: data) {
                    pasteboard.writeObjects([image])
                }
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
