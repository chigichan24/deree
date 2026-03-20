import Foundation
import IdentifiedCollections
import Testing

@testable import deree

// MARK: - Test Fixture

/// Minimal valid PNG image data (1x1 red pixel)
private let minimalPNGData: Data = {
    // PNG signature
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    // IHDR chunk (width=1, height=1, bit depth=8, color type=2 RGB)
    let ihdrData = Data([
        0x00, 0x00, 0x00, 0x01, // width
        0x00, 0x00, 0x00, 0x01, // height
        0x08,                   // bit depth
        0x02,                   // color type (RGB)
        0x00,                   // compression method
        0x00,                   // filter method
        0x00,                   // interlace method
    ])
    data.append(pngChunk(type: "IHDR", data: ihdrData))

    // IDAT chunk (compressed scanline: filter=0, R=255, G=0, B=0)
    let rawScanline = Data([0x00, 0xFF, 0x00, 0x00])
    let compressedData = deflateWrap(rawScanline)
    data.append(pngChunk(type: "IDAT", data: compressedData))

    // IEND chunk
    data.append(pngChunk(type: "IEND", data: Data()))

    return data
}()

/// Creates a wider PNG for thumbnail testing (300x200 pixels)
private let widePNGData: Data = {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    let ihdrData = Data([
        0x00, 0x00, 0x01, 0x2C, // width = 300
        0x00, 0x00, 0x00, 0xC8, // height = 200
        0x08,                   // bit depth
        0x02,                   // color type (RGB)
        0x00,                   // compression method
        0x00,                   // filter method
        0x00,                   // interlace method
    ])
    data.append(pngChunk(type: "IHDR", data: ihdrData))

    // IDAT: generate scanlines for 300x200 RGB image
    var rawData = Data()
    for _ in 0..<200 {
        rawData.append(0x00) // filter byte: None
        for _ in 0..<300 {
            rawData.append(contentsOf: [0xFF, 0x00, 0x00]) // red pixel
        }
    }
    let compressedData = deflateWrap(rawData)
    data.append(pngChunk(type: "IDAT", data: compressedData))

    data.append(pngChunk(type: "IEND", data: Data()))
    return data
}()

private func pngChunk(type: String, data: Data) -> Data {
    var chunk = Data()
    var length = UInt32(data.count).bigEndian
    chunk.append(Data(bytes: &length, count: 4))
    chunk.append(type.data(using: .ascii)!)
    chunk.append(data)

    // CRC32 over type + data
    var crcInput = type.data(using: .ascii)!
    crcInput.append(data)
    var crc = crc32(crcInput).bigEndian
    chunk.append(Data(bytes: &crc, count: 4))
    return chunk
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >>= 1
            }
        }
    }
    return crc ^ 0xFFFF_FFFF
}

/// zlib wrap: CMF + FLG + deflate stored block + Adler-32
private func deflateWrap(_ input: Data) -> Data {
    var out = Data()
    // zlib header (CM=8 deflate, CINFO=7 32K window, FCHECK adjusted)
    out.append(contentsOf: [0x78, 0x01])

    // Stored blocks (BFINAL=1, BTYPE=00)
    // Split into blocks of up to 65535 bytes
    let maxBlock = 65535
    var offset = 0
    while offset < input.count {
        let remaining = input.count - offset
        let blockSize = min(remaining, maxBlock)
        let isFinal: UInt8 = (offset + blockSize >= input.count) ? 0x01 : 0x00
        out.append(isFinal)
        var len = UInt16(blockSize)
        var nlen = ~len
        out.append(Data(bytes: &len, count: 2))
        out.append(Data(bytes: &nlen, count: 2))
        out.append(input[offset..<(offset + blockSize)])
        offset += blockSize
    }

    // Adler-32 checksum
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in input {
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    }
    var adler = ((b << 16) | a).bigEndian
    out.append(Data(bytes: &adler, count: 4))

    return out
}

// MARK: - Tests

struct StorageClientTests {
    private let tempDir: URL
    private let client: StorageClient

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deree-test-\(UUID().uuidString)")
        client = StorageClient.makeLive(baseDirectory: tempDir)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func saveImageCreatesFilesOnDisk() async throws {
        defer { cleanup() }

        let result = try await client.save(widePNGData)
        let image = result.saved

        let fullPath = tempDir.appendingPathComponent("full").appendingPathComponent(image.fullFileName)
        let thumbPath = tempDir.appendingPathComponent("thumb").appendingPathComponent(image.thumbnailFileName)

        #expect(FileManager.default.fileExists(atPath: fullPath.path))
        #expect(FileManager.default.fileExists(atPath: thumbPath.path))
        #expect(image.fullFileName == "full_\(image.id).png")
        #expect(image.thumbnailFileName == "thumb_\(image.id).png")
        #expect(result.evictedIDs.isEmpty)
    }

    @Test func loadAllReturnsNewestFirst() async throws {
        defer { cleanup() }

        let first = try await client.save(minimalPNGData).saved
        try await Task.sleep(for: .milliseconds(50))
        let second = try await client.save(minimalPNGData).saved

        let all = try await client.loadAll()

        #expect(all.count == 2)
        #expect(all[0].id == second.id)
        #expect(all[1].id == first.id)
    }

    @Test func deleteRemovesFilesFromDisk() async throws {
        defer { cleanup() }

        let image = try await client.save(widePNGData).saved

        let fullPath = tempDir.appendingPathComponent("full").appendingPathComponent(image.fullFileName)
        let thumbPath = tempDir.appendingPathComponent("thumb").appendingPathComponent(image.thumbnailFileName)

        #expect(FileManager.default.fileExists(atPath: fullPath.path))

        try await client.delete(image.id)

        #expect(!FileManager.default.fileExists(atPath: fullPath.path))
        #expect(!FileManager.default.fileExists(atPath: thumbPath.path))

        let all = try await client.loadAll()
        #expect(all.count == 0)
    }

    @Test func imageCapEnforcesMaximum50() async throws {
        defer { cleanup() }

        var firstSavedId: UUID?
        for i in 0..<StorageConstants.maxImageCount + 1 {
            let result = try await client.save(minimalPNGData)
            if i == 0 { firstSavedId = result.saved.id }
            if i == StorageConstants.maxImageCount {
                #expect(result.evictedIDs.contains(firstSavedId!))
            }
        }

        let all = try await client.loadAll()
        #expect(all.count == StorageConstants.maxImageCount)
    }

    @Test func thumbnailIsGeneratedAndLoadable() async throws {
        defer { cleanup() }

        let image = try await client.save(widePNGData).saved

        let thumbData = try await client.loadThumbnail(image.id)
        #expect(!thumbData.isEmpty)

        #expect(image.width == 300)
        #expect(image.height == 200)
    }

    @Test func saveAndLoadAllRoundTrip() async throws {
        defer { cleanup() }

        let saved = try await client.save(widePNGData).saved

        let all = try await client.loadAll()
        #expect(all.count == 1)
        #expect(all[0] == saved)

        let fullData = try await client.loadFull(saved.id)
        #expect(fullData == widePNGData)
    }

    // MARK: - Error cases

    @Test func saveInvalidData_throwsInvalidImageData() async {
        defer { cleanup() }

        await #expect(throws: StorageError.self) {
            _ = try await client.save(Data([0x00, 0x01, 0x02]))
        }
    }

    @Test func loadFull_nonexistentId_throwsImageNotFound() async {
        defer { cleanup() }

        let unknownId = UUID()
        await #expect(throws: StorageError.self) {
            _ = try await client.loadFull(unknownId)
        }
    }

    @Test func loadThumbnail_nonexistentId_throwsImageNotFound() async {
        defer { cleanup() }

        let unknownId = UUID()
        await #expect(throws: StorageError.self) {
            _ = try await client.loadThumbnail(unknownId)
        }
    }

    @Test func delete_nonexistentId_throwsImageNotFound() async {
        defer { cleanup() }

        let unknownId = UUID()
        await #expect(throws: StorageError.self) {
            try await client.delete(unknownId)
        }
    }
}
