import AnnoFormats
import Foundation
import Testing

@testable import AnnoSim

enum SimTestData {
    static let gameData: GameData? = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try? GameData.locate(currentDirectory: repoRoot)
    }()
}

@Suite("Straßenformen")
struct RoadShapeTests {
    @Test func shapesFromNeighbours() {
        #expect(Game.roadShape(mask: 0b0101) == (0, 1))
        #expect(Game.roadShape(mask: 0b1010) == (0, 0))
        #expect(Game.roadShape(mask: 0b0011) == (1, 0))
        #expect(Game.roadShape(mask: 0b1110) == (2, 1))
        #expect(Game.roadShape(mask: 0b1111) == (3, 0))
    }
}

@Suite("Bauen", .enabled(if: SimTestData.gameData != nil, "Spielordner nicht gefunden"))
struct BuildTests {
    let data = SimTestData.gameData!

    /// Ein Spiel auf dem Endlosszenario mit einer einzelnen bekannten Insel.
    func makeGame() throws -> Game {
        let buildings = try BuildingTable(gameData: data)
        let island = try IslandFile(bytes: data.read("Nord/big00.scp"))
        let placed = PlacedIsland(
            path: "Nord/big00.scp", map: IslandMap(island: island, buildings: buildings), x: 10, y: 10,
            climate: .north, hasNatives: false, deer: [])
        let world = WorldMap(width: 100, height: 90, islands: [placed], buildings: buildings)
        let player = Player(id: 0, money: 20000, shipCargo: Stock([.wood: 30, .tools: 50, .bricks: 0]))
        return Game(world: world, buildings: buildings, players: [player])
    }

    func findSpot(_ game: Game, _ type: BuildingType, rotation: Int = 0) -> (x: Int, y: Int)? {
        for y in 10..<70 {
            for x in 10..<80 where game.check(type, x: x, y: y, rotation: rotation, player: 0).isEmpty {
                return (x, y)
            }
        }
        return nil
    }

    @Test func kontorNeedsCoastAndUnloadsShip() throws {
        var game = try makeGame()
        let kontor = try #require(game.buildings[2101])
        #expect(kontor.buildCategory == .harbour)
        // Mitten im Meer und mitten im Inland geht es nicht.
        #expect(game.check(kontor, x: 0, y: 0, rotation: 0, player: 0) == [.notOnIsland])
        let spot = try #require(findSpot(game, kontor))
        let result = game.build(kontor, x: spot.x, y: spot.y, rotation: 0, player: 0)
        #expect(result.isEmpty)
        #expect(game.world.tile(x: spot.x, y: spot.y)?.building.kind == "HQ")
        let settlement = try #require(game.settlement(player: 0, island: 0))
        #expect(settlement.stock[.wood] == 30 - kontor.buildCost!.wood)
        #expect(game.players[0].shipCargo == Stock())
        #expect(game.players[0].money == 20000 - kontor.buildCost!.money)
        #expect(game.isInfluenced(x: spot.x, y: spot.y, by: 0))
        // Ein zweites Kontor auf derselben Insel ist nicht erlaubt.
        #expect(findSpot(game, kontor) == nil)
    }

    @Test func buildingsNeedInfluenceAndMaterial() throws {
        var game = try makeGame()
        let kontor = try #require(game.buildings[2101])
        let house = try #require(game.buildings[605])
        let anywhere = try #require(findSpotIgnoringInfluence(game, house))
        #expect(game.check(house, x: anywhere.x, y: anywhere.y, rotation: 0, player: 0).contains(.outsideInfluence))

        let spot = try #require(findSpot(game, kontor))
        game.build(kontor, x: spot.x, y: spot.y, rotation: 0, player: 0)
        let houseSpot = try #require(findSpot(game, house))
        let woodBefore = game.settlement(player: 0, island: 0)!.stock[.wood]
        let result = game.build(house, x: houseSpot.x, y: houseSpot.y, rotation: 0, player: 0)
        #expect(result.isEmpty)
        #expect(game.settlement(player: 0, island: 0)!.stock[.wood] == woodBefore - house.buildCost!.wood)
        // Zufallsvariante eines Wohnhauses wurde gesetzt.
        #expect(game.world.tile(x: houseSpot.x, y: houseSpot.y)?.building.production == "WOHNUNG")
    }

    func findSpotIgnoringInfluence(_ game: Game, _ type: BuildingType) -> (x: Int, y: Int)? {
        for y in 10..<70 {
            for x in 10..<80 where game.check(type, x: x, y: y, rotation: 0, player: 0) == [.outsideInfluence] {
                return (x, y)
            }
        }
        return nil
    }

    @Test func pavedRoadNeedsBricks() throws {
        var game = try makeGame()
        let kontor = try #require(game.buildings[2101])
        let stone = try #require(game.buildings[401])
        let spot = try #require(findSpot(game, kontor))
        game.build(kontor, x: spot.x, y: spot.y, rotation: 0, player: 0)
        #expect(stone.buildCost?.bricks == 1)
        // Ohne Ziegel im Lager scheitert jede Steinstraße.
        let anyFree = (10..<70).contains { y in
            (10..<80).contains { x in game.check(stone, x: x, y: y, rotation: 0, player: 0) == [.notEnough(.bricks)] }
        }
        #expect(anyFree)
    }

    @Test func roadsConnectAndDemolishRestoresGround() throws {
        var game = try makeGame()
        let kontor = try #require(game.buildings[2101])
        let road = try #require(game.buildings[411])  // Feldweg
        let spot = try #require(findSpot(game, kontor))
        game.build(kontor, x: spot.x, y: spot.y, rotation: 0, player: 0)
        game.players[0].money = 100_000
        // Freie 3×3-Fläche suchen und ein Kreuz bauen.
        var center: (Int, Int)?
        search: for y in 10..<70 {
            for x in 10..<80 {
                let cells = [(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                if cells.allSatisfy({ game.check(road, x: $0.0, y: $0.1, rotation: 0, player: 0).isEmpty }) {
                    center = (x, y)
                    break search
                }
            }
        }
        let (cx, cy) = try #require(center)
        let built = game.buildRoad(road, path: [(cx - 1, cy), (cx, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)], player: 0)
        #expect(built == 5)
        #expect(game.world.tile(x: cx, y: cy)?.building.id == 414)  // Kreuzung
        #expect(game.world.tile(x: cx - 1, y: cy)?.building.id == 411)  // Endstück gerade
        let demolished = game.demolish(x: cx, y: cy, player: 0)
        #expect(demolished)
        #expect(game.world.tile(x: cx, y: cy)?.building.kind == "BODEN")
        #expect(game.world.tile(x: cx, y: cy - 1)?.building.id == 411)  // wieder gerade
        // Gelände kann nicht abgerissen werden.
        let again = game.demolish(x: cx, y: cy, player: 0)
        #expect(!again)
    }

    @Test func roadPreviewShowsFinalShapes() throws {
        let game = try makeGame()
        let road = try #require(game.buildings[411])
        // L-förmiger Weg: drei Felder nach Osten, dann zwei nach Süden.
        let path = [(x: 20, y: 20), (x: 21, y: 20), (x: 22, y: 20), (x: 22, y: 21), (x: 22, y: 22)]
        let preview = game.roadPreview(road, path: path)
        #expect(preview.map(\.building.id) == [411, 411, 412, 411, 411])
        #expect(preview[2].rotation == 2)  // Kurve mit Anschlüssen West und Süd
        #expect(preview[0].rotation == 0 && preview[3].rotation == 1)
    }
}
