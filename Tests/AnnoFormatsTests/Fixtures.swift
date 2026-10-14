import Foundation

@testable import AnnoFormats

/// Baut Chunk- und BSH-Dateien für Tests ohne Originaldaten.
enum Fixtures {
    static func le32(_ value: Int) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    static func chunk(_ name: String, _ data: [UInt8], garbage: UInt8 = 0xAB) -> [UInt8] {
        var nameBytes = Array(name.utf8) + [0]
        nameBytes += Array(repeating: garbage, count: 16 - nameBytes.count)
        return nameBytes + le32(data.count) + data
    }

    /// BSH-Datei aus Bildern (width, height, RLE-Daten).
    static func bsh(_ images: [(width: Int, height: Int, rle: [UInt8])], chunkName: String = "BSH") -> [UInt8] {
        let tableSize = images.count * 4
        var bodies: [UInt8] = []
        var offsets: [Int] = []
        for image in images {
            offsets.append(tableSize + bodies.count)
            bodies += le32(image.width) + le32(image.height) + le32(1) + le32(image.rle.count) + image.rle
        }
        return chunk(chunkName, offsets.flatMap(le32) + bodies)
    }
}

/// Zugriff auf die Originaldaten, falls vorhanden (`OPEN1602_DATA` oder `ANNO1602/ANNO1602` im Repo).
enum TestData {
    static let gameData: GameData? = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try? GameData.locate(currentDirectory: repoRoot)
    }()

    static var available: Bool { gameData != nil }
}
