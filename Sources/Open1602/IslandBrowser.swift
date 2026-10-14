import AnnoFormats
import AnnoRender

/// Blättert durch alle Inselvorlagen (Nord, Süd, Eingeborene).
@MainActor
final class IslandBrowser: MapContent {
    private let gameData: GameData
    private let buildings: BuildingTable
    let files: [String]
    private(set) var fileIndex = 0
    private var map: IslandMap
    private var header: IslandHeader
    private var herd: Herd

    init(gameData: GameData, buildings: BuildingTable) throws {
        self.gameData = gameData
        self.buildings = buildings
        files = gameData.files(withExtension: "scp").filter {
            ["nord", "sued", "nordnat", "suednat"].contains($0.split(separator: "/").first?.lowercased() ?? "")
        }
        (map, header, herd) = try Self.load(files[0], gameData: gameData, buildings: buildings)
    }

    private static func load(_ path: String, gameData: GameData, buildings: BuildingTable) throws -> (IslandMap, IslandHeader, Herd) {
        let island = try IslandFile(bytes: gameData.read(path))
        let base = try IslandFile.baseTemplatePath(for: path).flatMap { p in
            gameData.url(for: p) != nil ? try IslandFile(bytes: gameData.read(p)) : nil
        }
        let map = IslandMap(island: island, base: base, buildings: buildings)
        let deer = island.deer.isEmpty ? (base?.deer ?? []) : island.deer
        let herd = Herd(
            positions: deer.map { SIMD2(Float($0.x) + 0.5, Float($0.y) + 0.5) }, seed: UInt64(path.hashValue & 0xFFFF),
            walkable: { x, y in Herd.isPasture(map.tile(x: x, y: y)) })
        return (map, island.header, herd)
    }

    var currentFile: String { files[fileIndex] }

    func select(file: String) throws {
        guard let index = files.firstIndex(where: { $0.lowercased() == file.lowercased() }) else { return }
        try select(index: index)
    }

    func next(_ delta: Int) throws {
        try select(index: ((fileIndex + delta) % files.count + files.count) % files.count)
    }

    private func select(index: Int) throws {
        fileIndex = index
        (map, header, herd) = try Self.load(currentFile, gameData: gameData, buildings: buildings)
    }

    var grid: any TileGrid { map }
    var focus: SIMD2<Float>? { nil }

    var title: String {
        var parts = ["\(currentFile)  \(header.width)×\(header.height)"]
        if !herd.deer.isEmpty { parts.append("\(herd.deer.count) Hirsche") }
        if !map.unknownBuildingIDs.isEmpty { parts.append("\(map.unknownBuildingIDs.count) unbekannte IDs") }
        if !map.isComplete { parts.append("unvollständig") }
        return parts.joined(separator: "  ·  ")
    }

    func update(dt: Double) { herd.update(dt: dt) }

    func figures(layout: IsometricLayout, library: SpriteLibrary, timeMs: Int) -> [FigureSprite] {
        herd.figures(layout: layout, library: library, timeMs: timeMs)
    }
}
