import Foundation

struct ClipboardImage: Equatable, Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let thumbnailFileName: String
    let fullFileName: String
    let width: Int
    let height: Int
}
