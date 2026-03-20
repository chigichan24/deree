import SwiftUI

struct ThumbnailView: View {
    let image: ClipboardImage
    let thumbnail: NSImage?

    @State private var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailContent
            timestampOverlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 2
                )
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(nsColor: .quaternarySystemFill))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private var timestampOverlay: some View {
        Text(image.createdAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(6)
    }
}

#Preview("With Placeholder") {
    ThumbnailView(
        image: ClipboardImage(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-120),
            width: 800,
            height: 600
        ),
        thumbnail: nil
    )
    .frame(width: 260)
    .padding()
}

#Preview("With Image") {
    let sampleImage: NSImage = {
        let img = NSImage(size: NSSize(width: 200, height: 150))
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: img.size))
        img.unlockFocus()
        return img
    }()

    return ThumbnailView(
        image: ClipboardImage(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-3600),
            width: 200,
            height: 150
        ),
        thumbnail: sampleImage
    )
    .frame(width: 260)
    .padding()
}
