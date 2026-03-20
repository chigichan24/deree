import AppKit
import ComposableArchitecture
import SwiftUI

struct ClipboardImageListView: View {
    let store: StoreOf<ClipboardFeature>

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(width: PanelConstants.width)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Clipboard Images")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var contentView: some View {
        Group {
            if store.images.isEmpty {
                EmptyStateView()
            } else {
                imageListView
            }
        }
    }

    private var imageListView: some View {
        let thumbnails = store.thumbnails
        return ScrollView(.vertical) {
            LazyVStack(spacing: 8) {
                ForEach(store.images) { image in
                    Button {
                        store.send(.copyImageToPasteboard(image.id))
                    } label: {
                        ThumbnailView(
                            image: image,
                            thumbnail: thumbnails[image.id].flatMap { NSImage(data: $0) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

#Preview("Empty State") {
    ClipboardImageListView(
        store: Store(
            initialState: ClipboardFeature.State()
        ) {
            ClipboardFeature()
        }
    )
    .frame(height: 500)
}

#Preview("With Images") {
    ClipboardImageListView(
        store: Store(
            initialState: ClipboardFeature.State(
                images: [
                    ClipboardImage(
                        id: UUID(),
                        createdAt: Date().addingTimeInterval(-60),
                        width: 800,
                        height: 600
                    ),
                    ClipboardImage(
                        id: UUID(),
                        createdAt: Date().addingTimeInterval(-300),
                        width: 1920,
                        height: 1080
                    ),
                    ClipboardImage(
                        id: UUID(),
                        createdAt: Date().addingTimeInterval(-3600),
                        width: 400,
                        height: 400
                    ),
                ]
            )
        ) {
            ClipboardFeature()
        }
    )
    .frame(height: 500)
}
