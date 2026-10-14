import AnnoFormats
import AnnoRender
import AnnoSim

/// Eine Welt aus einem Szenario: Inseln, Startschiffe, Hirsche.
@MainActor
final class WorldSession: MapContent {
    private let gameData: GameData
    private let buildings: BuildingTable
    private let figureGfx: [String: Int]
    let scenarioFiles: [String]
    private(set) var scenarioIndex: Int
    private(set) var seed: UInt64
    private(set) var scenario: Scenario
    /// Spielstand mit Bauregeln; die Welt darin wird beim Bauen verändert.
    private(set) var game: Game
    var world: WorldMap { game.world }
    private var worldIndex = 0
    private var herd: Herd
    private var ships: [(position: SIMD2<Float>, gfx: Int, direction: Int)] = []

    init(gameData: GameData, buildings: BuildingTable, seed: UInt64 = 1602) throws {
        self.gameData = gameData
        self.buildings = buildings
        self.seed = seed
        // Bildnummern der Figuren (z. B. HANDEL1 → 0 in SHIP.BSH).
        let figures = COD.parse(encrypted: try gameData.read("figuren.cod"))
        var gfx: [String: Int] = [:]
        for (name, value) in figures.variables {
            if let number = value.intValue, let item = figures.collections["FIGUR"]?[number], let g = item.int("Gfx") {
                gfx[name] = g
            }
        }
        figureGfx = gfx
        scenarioFiles = gameData.files(withExtension: "cod").filter { $0.lowercased().hasPrefix("szenes/") }
        scenarioIndex = scenarioFiles.firstIndex { $0.lowercased().hasSuffix("endless0.cod") } ?? 0
        scenario = try Self.loadScenario(scenarioFiles[scenarioIndex], gameData: gameData)
        game = Game(world: WorldMap(width: 1, height: 1, islands: [], buildings: buildings), buildings: buildings, players: [])
        herd = Herd(positions: [], seed: 0, walkable: { _, _ in false })
        try generate()
    }

    private static func loadScenario(_ path: String, gameData: GameData) throws -> Scenario {
        try Scenario(document: COD.parse(encrypted: gameData.read(path)))
    }

    func select(scenario file: String) throws {
        guard let index = scenarioFiles.firstIndex(where: { $0.lowercased() == file.lowercased() }) else { return }
        scenarioIndex = index
        scenario = try Self.loadScenario(scenarioFiles[index], gameData: gameData)
        try generate()
    }

    func nextScenario(_ delta: Int) throws {
        let count = scenarioFiles.count
        try select(scenario: scenarioFiles[((scenarioIndex + delta) % count + count) % count])
    }

    /// Neue Zufallswelt mit anderem Startwert.
    func reroll(seed: UInt64? = nil) throws {
        self.seed = seed ?? (self.seed &* 6_364_136_223_846_793_005 &+ 1)
        try generate()
    }

    private func generate() throws {
        var rng = SeededRandom(seed: seed)
        worldIndex = scenario.worlds.isEmpty ? 0 : Int.random(in: 0..<scenario.worlds.count, using: &rng)
        let world = try WorldMap.generate(
            scenario: scenario, worldIndex: worldIndex, seed: rng.next(), gameData: gameData, buildings: buildings)
        game = Game(world: world, buildings: buildings, scenario: scenario, seed: seed)
        revision += 1
        let deer = world.islands.flatMap { island in
            island.deer.map { SIMD2(Float(island.x + $0.x) + 0.5, Float(island.y + $0.y) + 0.5) }
        }
        herd = Herd(positions: deer, seed: seed, walkable: { [weak self] x, y in Herd.isPasture(self?.game.world.tile(x: x, y: y)) })
        let positions = scenario.worlds.isEmpty ? [:] : scenario.worlds[worldIndex].shipPositions
        ships = scenario.ships.compactMap { ship in
            guard let p = positions[ship.player] else { return nil }
            return (SIMD2(Float(p.x) + 0.5, Float(p.y) + 0.5), figureGfx[ship.figure] ?? 0, ship.direction)
        }
    }

    var grid: any TileGrid { game.world }

    /// Zählt Änderungen an der Welt (für die Minikarte).
    private(set) var revision = 0

    /// Spielaktionen (Bauen, Abreißen) laufen über diese Methode, damit die Welt neu gezeichnet wird.
    func mutateGame<T>(_ body: (inout Game) -> T) -> T {
        revision += 1
        return body(&game)
    }
    var focus: SIMD2<Float>? {
        if let ship = ships.first { return ship.position }
        // Ohne Startschiff (Tutorials, Kakao02) auf die erste Insel schauen.
        return world.islands.first.map { SIMD2(Float($0.x + $0.map.width / 2), Float($0.y + $0.map.height / 2)) }
    }

    var title: String {
        "\(scenario.name) (\(scenarioFiles[scenarioIndex].split(separator: "/").last ?? ""))  ·  Welt \(worldIndex + 1)/\(max(scenario.worlds.count, 1)), Startwert \(seed)  ·  \(world.islands.count) Inseln, \(world.islands.filter(\.hasNatives).count) mit Eingeborenen"
    }

    func update(dt: Double) { herd.update(dt: dt) }

    func figures(layout: IsometricLayout, library: SpriteLibrary, timeMs: Int) -> [FigureSprite] {
        var figures = herd.figures(layout: layout, library: library, timeMs: timeMs)
        for ship in ships {
            // Die Blickrichtung dreht sich mit der Kamera (zwei Schritte pro Vierteldrehung).
            let direction = (ship.direction + 2 * layout.rotation) % 8
            let index = library.index("SHIP", ship.gfx + direction)
            guard let size = library.size(of: index) else { continue }
            figures.append(FigureSprite(
                position: ship.position, index: index,
                anchor: SIMD2(Float(size.width) / 2, Float(size.height) - Float(layout.zoom.scaled(34)))))
        }
        return figures
    }
}
