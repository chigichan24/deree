import Foundation

struct ClipboardImage: Equatable, Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let width: Int
    let height: Int

    static func fullFileName(for id: UUID) -> String { "full_\(id).png" }
    static func thumbFileName(for id: UUID) -> String { "thumb_\(id).png" }

    var thumbnailFileName: String { Self.thumbFileName(for: id) }
    var fullFileName: String { Self.fullFileName(for: id) }
    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, width, height
    }

    private static func areDimensionsValid(width: Int, height: Int) -> Bool {
        width > 0 && height > 0
    }

    init(id: UUID, createdAt: Date, width: Int, height: Int) {
        guard Self.areDimensionsValid(width: width, height: height) else {
            fatalError("Image dimensions must be positive (got \(width)x\(height))")
        }
        self.id = id
        self.createdAt = createdAt
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        guard Self.areDimensionsValid(width: width, height: height) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Image dimensions must be positive (got \(width)x\(height))"
                )
            )
        }
    }
}
