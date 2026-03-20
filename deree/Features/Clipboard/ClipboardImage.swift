import Foundation

struct ClipboardImage: Equatable, Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let thumbnailFileName: String
    let fullFileName: String
    let width: Int
    let height: Int

    init(id: UUID, createdAt: Date, thumbnailFileName: String, fullFileName: String, width: Int, height: Int) {
        precondition(width > 0 && height > 0, "Image dimensions must be positive")
        self.id = id
        self.createdAt = createdAt
        self.thumbnailFileName = thumbnailFileName
        self.fullFileName = fullFileName
        self.width = width
        self.height = height
    }
}
