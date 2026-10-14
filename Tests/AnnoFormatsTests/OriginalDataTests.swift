import Testing

@testable import AnnoFormats

/// Tests gegen die echten Originaldaten. Werden übersprungen, wenn kein Spielordner gefunden wird.
@Suite("Originaldaten", .enabled(if: TestData.available, "Spielordner nicht gefunden (OPEN1602_DATA setzen)"))
struct OriginalDataTests {
    let data = TestData.gameData!

    @Test func paletteLoads() throws {
        let palette = try Palette(colFile: data.read("ToolGfx/STADTFLD.COL"))
        #expect(palette.colors.count == 256)
    }

    @Test func stadtfeldSprites() throws {
        let archive = try BSHArchive(fileBytes: data.read("GFX/STADTFLD.BSH"))
        #expect(archive.count == 5748)
        let tile = try archive.image(at: 0)
        #expect(tile.width == 64 && tile.height == 31)
        let mill = try archive.image(at: 2000)
        #expect(mill.width == 64 && mill.height == 114)
    }

    @Test func zoomLevelsHaveSmallerTiles() throws {
        let medium = try BSHArchive(fileBytes: data.read("MGFX/STADTFLD.BSH")).header(at: 0)
        let small = try BSHArchive(fileBytes: data.read("SGFX/STADTFLD.BSH")).header(at: 0)
        #expect(medium.width == 32)
        #expect(small.width == 16)
    }

    @Test func startScreen() throws {
        let image = try BSHArchive(fileBytes: data.read("ToolGfx/START.BSH")).image(at: 0)
        #expect(image.width == 1024 && image.height == 768)
    }

    @Test(arguments: TestData.gameData?.files(withExtension: "bsh") ?? [])
    func everyBSHDecodes(path: String) throws {
        let archive = try BSHArchive(fileBytes: data.read(path))
        #expect(archive.count > 0)
        for i in 0..<archive.count {
            _ = try archive.image(at: i)
        }
    }

    @Test func islandChunks() throws {
        let chunks = try Chunk.readAll(data.read("Nord/big00.scp"))
        #expect(chunks.map(\.name) == ["INSEL3", "INSELHAUS"])
    }
}
