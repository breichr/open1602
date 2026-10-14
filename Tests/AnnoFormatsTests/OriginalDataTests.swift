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

@Suite("Inseln", .enabled(if: TestData.available, "Spielordner nicht gefunden (OPEN1602_DATA setzen)"))
struct IslandDataTests {
    let data = TestData.gameData!

    @Test func haeuserCodParsesCompletely() throws {
        let doc = COD.parse(encrypted: try data.read("haeuser.cod"))
        #expect(doc.unparsedLines.isEmpty)
        #expect(doc.items("HAUS").count == 491)
        let table = BuildingTable(cod: doc)
        #expect(table[1201]?.kind == "MEER")
        #expect(table[1201]?.gfx == 758)
        #expect(table[1110]?.width == 6)
    }

    @Test func figurenCodParsesCompletely() throws {
        let doc = COD.parse(encrypted: try data.read("figuren.cod"))
        #expect(doc.unparsedLines.isEmpty)
        #expect(doc.items("FIGUR").count == 96)
    }

    @Test func islandHeader() throws {
        let island = try IslandFile(bytes: data.read("Nord/big00.scp"))
        #expect(island.header.width == 70 && island.header.height == 60)
        #expect(island.fields.count == 4084)
    }

    /// Jede Inselvorlage (Nord/Süd) muss vollständig und mit gültigen Bildindizes aufgehen.
    /// Besiedelte Varianten werden auf ihre Basisvorlage gelegt.
    @Test(arguments: TestData.gameData?.files(withExtension: "scp").filter {
        let dir = $0.split(separator: "/").first?.lowercased()
        return dir == "nord" || dir == "sued"
    } ?? [])
    func templateIslandIsComplete(path: String) throws {
        // Bekannte Eigenheiten der Originaldaten.
        let wrongBase = ["Nord/big13s19.scp"]  // 30×30, Basis big13 ist 70×60
        let duplicateFields = ["Nord/big04s14.scp", "Sued/med04s11.scp"]

        let table = try BuildingTable(gameData: data)
        let spriteCount = try BSHArchive(fileBytes: data.read("GFX/STADTFLD.BSH")).count
        let island = try IslandFile(bytes: data.read(path))
        let base = try IslandFile.baseTemplatePath(for: path).map { try IslandFile(bytes: data.read($0)) }
        let map = IslandMap(island: island, base: base, buildings: table)
        #expect(map.unknownBuildingIDs.isEmpty)
        #expect(map.outOfBounds == 0)
        #expect(map.overlaps == 0 || duplicateFields.contains(path))
        #expect(map.isComplete || wrongBase.contains(path), "Insel hat leere Felder")
        for tile in map.tiles.compactMap({ $0 }) {
            for rotation in 0..<4 {
                let (fw, fh) = tile.building.footprint(rotation: tile.rotation + rotation)
                let index = tile.building.spriteIndex(
                    rotation: tile.rotation + rotation, animation: tile.animation, dx: tile.dx % fw, dy: tile.dy % fh)
                #expect((0..<spriteCount).contains(index))
            }
        }
    }

    @Test func baseTemplatePaths() {
        #expect(IslandFile.baseTemplatePath(for: "Nord/big01s16.scp") == "Nord/big01.scp")
        #expect(IslandFile.baseTemplatePath(for: "Sued/med08c.scp") == "Sued/med08.scp")
        #expect(IslandFile.baseTemplatePath(for: "Nord/big01.scp") == nil)
        #expect(IslandFile.baseTemplatePath(for: "Nord/large03.scp") == nil)
    }
}
