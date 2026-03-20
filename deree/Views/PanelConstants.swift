import AppKit

enum PanelConstants {
    static let width: CGFloat = 280

    static func frame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        return NSRect(
            x: screenFrame.maxX - width,
            y: screenFrame.origin.y,
            width: width,
            height: screenFrame.height
        )
    }
}
