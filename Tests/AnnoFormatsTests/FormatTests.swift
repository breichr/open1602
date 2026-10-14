import Foundation
import Testing

@testable import AnnoFormats

@Suite("Chunk")
struct ChunkTests {
    @Test func readsSequenceIgnoringGarbageAfterName() throws {
        let bytes = Fixtures.chunk("INSEL3", [1, 2, 3]) + Fixtures.chunk("INSELHAUS", [])
        let chunks = try Chunk.readAll(bytes)
        #expect(chunks.map(\.name) == ["INSEL3", "INSELHAUS"])
        #expect(chunks[0].data == [1, 2, 3])
        #expect(chunks[1].data.isEmpty)
    }

    @Test func truncatedDataThrows() {
        let bytes = Array(Fixtures.chunk("BSH", [1, 2, 3, 4]).dropLast())
        #expect(throws: FormatError.self) { try Chunk.readAll(bytes) }
    }

    @Test func wrongChunkNameThrows() {
        #expect(throws: FormatError.unexpectedChunk(expected: "COL", found: "BSH")) {
            try Chunk.readFirst(Fixtures.chunk("BSH", []), named: "COL")
        }
    }
}

@Suite("Palette")
struct PaletteTests {
    @Test func readsRGBXEntries() throws {
        var data = [UInt8](repeating: 0, count: 1024)
        data[4..<8] = [10, 20, 30, 0]
        data[1020..<1024] = [255, 0, 255, 0]
        let palette = try Palette(colFile: Fixtures.chunk("COL", data))
        #expect(palette[1] == RGBColor(r: 10, g: 20, b: 30))
        #expect(palette[255] == RGBColor(r: 255, g: 0, b: 255))
    }

    @Test func wrongSizeThrows() {
        #expect(throws: FormatError.invalidPalette(byteCount: 12)) {
            try Palette(colFile: Fixtures.chunk("COL", [UInt8](repeating: 0, count: 12)))
        }
    }
}

@Suite("BSH")
struct BSHTests {
    // 3×2-Bild:  . A B
    //            C . .
    static let rle: [UInt8] = [1, 2, 0xA, 0xB, 0xFE, 0, 1, 0xC, 0xFE, 0xFF]

    @Test func decodesRLEWithTransparency() throws {
        let archive = try BSHArchive(fileBytes: Fixtures.bsh([(3, 2, Self.rle)]))
        #expect(archive.count == 1)
        let image = try archive.image(at: 0)
        #expect(image.width == 3 && image.height == 2)
        #expect(image.indices == [0, 0xA, 0xB, 0xC, 0, 0])
        #expect(image.opaque == [false, true, true, true, false, false])
    }

    @Test func multipleImagesAndHeaders() throws {
        let archive = try BSHArchive(fileBytes: Fixtures.bsh([(3, 2, Self.rle), (1, 1, [0, 1, 7, 0xFF])]))
        #expect(archive.count == 2)
        #expect(try archive.header(at: 1) == BSHImageHeader(width: 1, height: 1, type: 1, length: 4))
        #expect(try archive.image(at: 1).indices == [7])
    }

    @Test func rgbaUsesPaletteAndAlpha() throws {
        let image = try BSHArchive(fileBytes: Fixtures.bsh([(3, 2, Self.rle)])).image(at: 0)
        var colors = [RGBColor](repeating: RGBColor(r: 0, g: 0, b: 0), count: 256)
        colors[0xA] = RGBColor(r: 1, g: 2, b: 3)
        let rgba = image.rgba(palette: Palette(colors: colors))
        #expect(Array(rgba[0..<8]) == [0, 0, 0, 0, 1, 2, 3, 255])
    }

    @Test func overflowingRLEThrows() {
        let tooWide: [UInt8] = [2, 2, 1, 2, 0xFF]
        #expect(throws: FormatError.rleOverflow(image: 0)) {
            try BSHArchive(fileBytes: Fixtures.bsh([(3, 1, tooWide)])).image(at: 0)
        }
    }

    @Test func missingEndMarkerThrows() {
        #expect(throws: FormatError.self) {
            try BSHArchive(fileBytes: Fixtures.bsh([(3, 1, [0, 1, 5])])).image(at: 0)
        }
    }

    @Test func zeiUsesSameLayout() throws {
        let archive = try BSHArchive(fileBytes: Fixtures.bsh([(3, 2, Self.rle)], chunkName: "ZEI"), chunkName: "ZEI")
        #expect(try archive.image(at: 0).width == 3)
    }
}

@Suite("GameData")
struct GameDataTests {
    func makeGameDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open1602-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sgfx"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("haeuser.cod"))
        try Data([1, 2]).write(to: root.appendingPathComponent("Sgfx/Stadtfld.bsh"))
        return root
    }

    @Test func resolvesPathsCaseInsensitively() throws {
        let root = try makeGameDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try GameData(root: root)
        #expect(try data.read("SGFX/STADTFLD.BSH") == [1, 2])
        #expect(try data.read("./sgfx//stadtfld.bsh") == [1, 2])
        #expect(data.files(withExtension: "BSH") == ["Sgfx/Stadtfld.bsh"])
        #expect(throws: GameData.Error.self) { try data.read("GFX/STADTFLD.BSH") }
    }

    @Test func rejectsDirectoryWithoutMarker() {
        #expect(throws: GameData.Error.self) {
            try GameData(root: FileManager.default.temporaryDirectory)
        }
    }

    @Test func locatePrefersEnvironment() throws {
        let root = try makeGameDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try GameData.locate(environment: [GameData.environmentKey: root.path], currentDirectory: URL(fileURLWithPath: "/"))
        #expect(data.root == root.standardizedFileURL.resolvingSymlinksInPath())
    }
}
