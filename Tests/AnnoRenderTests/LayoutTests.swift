import AnnoFormats
import Testing

@testable import AnnoRender

@Suite("IsometricLayout")
struct LayoutTests {
    struct Flat: TileGrid {
        let width: Int
        let height: Int
        let ground = BuildingType(
            id: 1, number: 0, gfx: 0, kind: "BODEN", width: 1, height: 1, rotateStride: 0,
            animationCount: 0, animationStride: 0, randomCount: 1, randomStride: 0, elevation: 0)
        func tile(x: Int, y: Int) -> IslandTile? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return IslandTile(building: ground, fieldIndex: 0, rotation: 0, animation: 0, random: 0, dx: 0, dy: 0)
        }
    }

    @Test(arguments: 0..<4) func cullingKeepsEverythingVisible(rotation: Int) {
        let grid = Flat(width: 60, height: 40)
        let layout = IsometricLayout(mapWidth: 60, mapHeight: 40, rotation: rotation, zoom: .medium)
        let size: (Int) -> (width: Int, height: Int)? = { _ in (32, 15) }
        let all = layout.sprites(for: grid, spriteSize: size)
        #expect(all.count == 60 * 40)
        let view = (min: SIMD2<Float>(-100, 100), max: SIMD2<Float>(300, 400))
        let culled = layout.sprites(for: grid, visible: view, spriteSize: size)
        let inView: (SpriteDraw) -> Bool = { d in
            d.position.x + 32 > view.min.x && d.position.x < view.max.x && d.position.y + 15 > view.min.y && d.position.y < view.max.y
        }
        #expect(culled.count < all.count)
        #expect(all.filter(inView).count == culled.filter(inView).count)
    }

    @Test(arguments: 0..<4) func screenAndMapPositionsRoundTrip(rotation: Int) {
        let layout = IsometricLayout(mapWidth: 50, mapHeight: 30, rotation: rotation, zoom: .large)
        let p = SIMD2<Float>(12.25, 7.5)
        let back = layout.mapPosition(ofScreen: layout.screen(ofPixel: layout.pixel(ofScreen: layout.screenPosition(ofMap: p))))
        #expect(abs(back.x - p.x) < 0.001 && abs(back.y - p.y) < 0.001)
    }

    @Test func animationAdvancesWithTime() {
        var water = BuildingType(
            id: 1201, number: 0, gfx: 100, kind: "MEER", width: 1, height: 1, rotateStride: 0,
            animationCount: 6, animationStride: 1, randomCount: 1, randomStride: 0, elevation: 0)
        water.animationTime = 130
        let tile = IslandTile(building: water, fieldIndex: 0, rotation: 0, animation: 2, random: 0, dx: 0, dy: 0)
        let layout = IsometricLayout(mapWidth: 1, mapHeight: 1, rotation: 0, zoom: .large)
        #expect(layout.spriteIndex(tile, timeMs: 0) == 102)
        #expect(layout.spriteIndex(tile, timeMs: 130 * 5) == 101)
    }

    /// Ein hohes Figurenbild (Schiff) muss nach allen Kacheln gezeichnet werden, die es überdeckt.
    @Test func tallFigureIsDrawnAfterCoveredTiles() {
        let grid = Flat(width: 10, height: 10)
        let layout = IsometricLayout(mapWidth: 10, mapHeight: 10, rotation: 0, zoom: .large)
        let shipIndex = 999
        let ship = FigureSprite(position: SIMD2(4.5, 4.5), index: shipIndex, anchor: SIMD2(60, 40))
        let draws = layout.sprites(for: grid, figures: [ship]) { index in
            index == shipIndex ? (120, 120) : (64, 31)
        }
        let shipDraw = draws.firstIndex { $0.index == shipIndex }!
        let shipBottom = draws[shipDraw].position.y + 120
        let shipLeft = draws[shipDraw].position.x
        // Keine später gezeichnete Kachel darf mit ihrer Oberkante über der Unterkante des Schiffs liegen
        // und es horizontal überlappen.
        for tile in draws[(shipDraw + 1)...] {
            let overlapsX = tile.position.x < shipLeft + 120 && tile.position.x + 64 > shipLeft
            #expect(!(overlapsX && tile.position.y < shipBottom - 31), "Kachel bei \(tile.position) übermalt das Schiff")
        }
    }
}
