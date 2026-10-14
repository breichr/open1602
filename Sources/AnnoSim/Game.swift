import AnnoFormats

/// Ein Spieler mit Geld und dem Laderaum seines Startschiffs.
public struct Player: Sendable {
    public let id: Int
    public var money: Int
    public var shipCargo: Stock
}

/// Besitz eines Spielers auf einer Insel: Kontore (Einfluss) und das gemeinsame Lager.
public struct Settlement: Sendable {
    public let player: Int
    public let island: Int
    public var stock: Stock
    /// Mittelpunkte der Einflussbereiche (Weltkoordinaten) mit Radius in Feldern.
    public var centers: [(x: Float, y: Float, radius: Float)]
}

/// Warum ein Gebäude an einer Stelle nicht gebaut werden kann.
public enum PlacementProblem: Equatable, Sendable, CustomStringConvertible {
    case notOnIsland
    case blocked
    case needsCoast
    case needsBeach
    case needsSlope
    case outsideInfluence
    case foreignTerritory
    case notEnoughMoney
    case notEnough(Ware)
    case notBuildable

    public var description: String {
        switch self {
        case .notOnIsland: "Nicht auf einer Insel"
        case .blocked: "Platz ist belegt"
        case .needsCoast: "Kontore müssen an der Küste stehen"
        case .needsBeach: "Muss am Strand stehen"
        case .needsSlope: "Muss an einem Berghang stehen"
        case .outsideInfluence: "Außerhalb des eigenen Einflussbereichs"
        case .foreignTerritory: "Gebiet eines anderen Spielers"
        case .notEnoughMoney: "Nicht genug Geld"
        case .notEnough(let ware): "Nicht genug \(ware.rawValue.capitalized)"
        case .notBuildable: "Kann nicht gebaut werden"
        }
    }
}

/// Spielstand mit den Bauregeln. Arbeitet in Weltkoordinaten.
public struct Game: Sendable {
    public private(set) var world: WorldMap
    public let buildings: BuildingTable
    public internal(set) var players: [Player]
    public private(set) var settlements: [Settlement] = []
    private var rng: SeededRandom
    /// Typischer Boden je Insel (für Abriss).
    private var groundCache: [Int: BuildingType] = [:]

    /// Einflussradius eines Kontors. `RADIUS_HQ` ist eine Programmkonstante; der Wert ist geschätzt.
    public static let kontorRadius: Float = 13

    public init(world: WorldMap, buildings: BuildingTable, players: [Player], seed: UInt64 = 1602) {
        self.world = world
        self.buildings = buildings
        self.players = players
        rng = SeededRandom(seed: seed)
    }

    /// Spiel aus einem Szenario: Startgeld und Schiffsladung je Spieler.
    public init(world: WorldMap, buildings: BuildingTable, scenario: Scenario, seed: UInt64 = 1602) {
        let players = (0..<max(scenario.ships.count, 1)).map { index -> Player in
            var cargo = Stock()
            for (name, amount) in scenario.shipCargo.indices.contains(index) ? scenario.shipCargo[index] : [:] {
                if let ware = Ware(rawValue: name) { cargo[ware] += amount }
            }
            return Player(id: index, money: scenario.money, shipCargo: cargo)
        }
        self.init(world: world, buildings: buildings, players: players, seed: seed)
    }

    // MARK: Abfragen

    public func settlement(player: Int, island: Int) -> Settlement? {
        settlements.first { $0.player == player && $0.island == island }
    }

    /// Liegt das Feld im Einflussbereich des Spielers?
    public func isInfluenced(x: Int, y: Int, by player: Int) -> Bool {
        guard let island = world.islandIndex(atX: x, y: y) else { return false }
        return settlements.contains { s in
            s.player == player && s.island == island && s.centers.contains { c in
                let dx = Float(x) + 0.5 - c.x
                let dy = Float(y) + 0.5 - c.y
                return dx * dx + dy * dy <= c.radius * c.radius
            }
        }
    }

    private func isForeign(x: Int, y: Int, player: Int) -> Bool {
        players.indices.contains { $0 != player && isInfluenced(x: x, y: y, by: $0) }
    }

    /// Boden, auf dem ohne Weiteres gebaut werden darf (Bäume werden dabei gerodet).
    static func isBuildableGround(_ tile: IslandTile?) -> Bool {
        guard let tile, tile.building.elevation > 0 else { return false }
        return tile.building.kind == "BODEN" || tile.building.kind == "WALD"
    }

    static func isBeach(_ tile: IslandTile?) -> Bool {
        tile?.building.kind.hasPrefix("STRAND") ?? false
    }

    static func isWaterOrBeach(_ tile: IslandTile?) -> Bool {
        guard let tile else { return true }
        return tile.building.elevation == 0
    }

    /// Prüft, ob `type` mit Ursprungsecke `(x, y)` gebaut werden darf.
    public func check(_ type: BuildingType, x: Int, y: Int, rotation: Int, player: Int) -> [PlacementProblem] {
        guard let cost = type.buildCost else { return [.notBuildable] }
        let (w, h) = type.footprint(rotation: rotation)
        guard let island = world.islandIndex(atX: x, y: y) else { return [.notOnIsland] }
        var problems: [PlacementProblem] = []
        var cells: [(Int, Int)] = []
        for dy in 0..<h {
            for dx in 0..<w { cells.append((x + dx, y + dy)) }
        }
        guard cells.allSatisfy({ world.islandIndex(atX: $0.0, y: $0.1) == island }) else { return [.notOnIsland] }

        let isKontor = type.production == "KONTOR"
        let tiles = cells.map { world.tile(x: $0.0, y: $0.1) }
        switch type.kind {
        case "STRANDHAUS", "PIER", "TURMSTRAND", "MAUERSTRAND":
            if !tiles.allSatisfy(Self.isBeach) { problems.append(.needsBeach) }
        case "MINE":
            if !tiles.allSatisfy({ $0?.building.kind.hasPrefix("HANG") ?? false }) { problems.append(.needsSlope) }
        case "BRUECKE":
            if !tiles.allSatisfy({ $0?.building.kind == "FLUSS" }) { problems.append(.blocked) }
        default:
            if !tiles.allSatisfy(Self.isBuildableGround) { problems.append(.blocked) }
        }

        if cells.contains(where: { isForeign(x: $0.0, y: $0.1, player: player) }) {
            problems.append(.foreignTerritory)
        }
        let existing = settlement(player: player, island: island)
        if isKontor {
            // Mindestens ein Nachbarfeld des Grundrisses liegt am Wasser.
            let ring = (x - 1...x + w).flatMap { xx in [(xx, y - 1), (xx, y + h)] } + (y...y + h - 1).flatMap { yy in [(x - 1, yy), (x + w, yy)] }
            if !ring.contains(where: { Self.isWaterOrBeach(world.tile(x: $0.0, y: $0.1)) }) { problems.append(.needsCoast) }
            if existing != nil { problems.append(.blocked) }
        } else if !cells.allSatisfy({ isInfluenced(x: $0.0, y: $0.1, by: player) }) {
            problems.append(.outsideInfluence)
        }

        // Kosten: Geld vom Spieler, Material aus dem Inselkontor (beim ersten Kontor aus dem Schiff).
        let playerState = players[player]
        if playerState.money < cost.money { problems.append(.notEnoughMoney) }
        let stock = existing?.stock ?? playerState.shipCargo
        for (ware, amount) in [(Ware.wood, cost.wood), (.tools, cost.tools), (.bricks, cost.bricks)] where stock[ware] < amount {
            problems.append(.notEnough(ware))
        }
        return problems
    }

    /// Legt Waren in das Lager eines Spielers auf einer Insel (z. B. Schiff entladen).
    public mutating func addToStock(player: Int, island: Int, _ goods: Stock) {
        guard let index = settlements.firstIndex(where: { $0.player == player && $0.island == island }) else { return }
        settlements[index].stock.add(goods)
    }

    // MARK: Bauen

    /// Baut `type`, wenn es erlaubt ist. Liefert die Probleme, falls nicht gebaut wurde.
    @discardableResult
    public mutating func build(_ type: BuildingType, x: Int, y: Int, rotation: Int, player: Int) -> [PlacementProblem] {
        let problems = check(type, x: x, y: y, rotation: rotation, player: player)
        guard problems.isEmpty, let cost = type.buildCost, let island = world.islandIndex(atX: x, y: y) else { return problems }
        let rotation = type.rotateStride > 0 ? ((rotation % 4) + 4) % 4 : 0

        // Zufallsvariante (z. B. Wohnhäuser, Baumarten).
        var placed = type
        if type.randomCount > 1 {
            let variant = Int.random(in: 0..<type.randomCount, using: &rng)
            placed = buildings[type.id + variant * type.randomStride] ?? type
        }

        players[player].money -= cost.money
        if let index = settlements.firstIndex(where: { $0.player == player && $0.island == island }) {
            settlements[index].stock[.wood] -= cost.wood
            settlements[index].stock[.tools] -= cost.tools
            settlements[index].stock[.bricks] -= cost.bricks
        } else {
            // Erstes Kontor: Material vom Schiff, der Rest wird ins Kontor entladen.
            var cargo = players[player].shipCargo
            cargo[.wood] -= cost.wood
            cargo[.tools] -= cost.tools
            cargo[.bricks] -= cost.bricks
            players[player].shipCargo = Stock()
            settlements.append(Settlement(player: player, island: island, stock: cargo, centers: []))
        }

        let origin = world.islands[island]
        world.modifyIsland(island) { $0.place(placed, x: x - origin.x, y: y - origin.y, rotation: rotation) }

        if type.production == "KONTOR", let index = settlements.firstIndex(where: { $0.player == player && $0.island == island }) {
            let (w, h) = type.footprint(rotation: rotation)
            settlements[index].centers.append((Float(x) + Float(w) / 2, Float(y) + Float(h) / 2, Float(type.radius ?? 0) > 0 ? Float(type.radius!) : Self.kontorRadius))
        }
        if type.kind == "STRASSE" { updateRoads(around: x, y: y) }
        return []
    }

    /// Baut Straßen auf einem Pfad; bereits vorhandene Straßen werden übersprungen.
    @discardableResult
    public mutating func buildRoad(_ type: BuildingType, path: [(x: Int, y: Int)], player: Int) -> Int {
        var built = 0
        for cell in path where world.tile(x: cell.x, y: cell.y)?.building.kind != "STRASSE" {
            if build(type, x: cell.x, y: cell.y, rotation: 0, player: player).isEmpty { built += 1 }
        }
        return built
    }

    /// Reißt das Gebäude auf Feld `(x, y)` ab. Gelände (Boden, Meer, Fels …) bleibt.
    @discardableResult
    public mutating func demolish(x: Int, y: Int, player: Int) -> Bool {
        guard let island = world.islandIndex(atX: x, y: y), isInfluenced(x: x, y: y, by: player),
            let tile = world.tile(x: x, y: y), Self.demolishable.contains(tile.building.kind)
        else { return false }
        let origin = world.islands[island]
        guard let fp = world.islands[island].map.footprint(atX: x - origin.x, y: y - origin.y) else { return false }
        let ground = groundBuilding(island: island)
        world.modifyIsland(island) { map in
            for dy in 0..<fp.height {
                for dx in 0..<fp.width { map.place(ground, x: fp.x + dx, y: fp.y + dy, rotation: 0) }
            }
        }
        if tile.building.production == "KONTOR", let index = settlements.firstIndex(where: { $0.player == player && $0.island == island }) {
            let cx = Float(origin.x + fp.x) + Float(fp.width) / 2
            let cy = Float(origin.y + fp.y) + Float(fp.height) / 2
            settlements[index].centers.removeAll { abs($0.x - cx) < 0.01 && abs($0.y - cy) < 0.01 }
        }
        if tile.building.kind == "STRASSE" { updateRoads(around: x, y: y) }
        return true
    }

    static let demolishable: Set<String> = [
        "GEBAEUDE", "STRASSE", "HQ", "BRUECKE", "PLATZ", "MAUER", "MAUERSTRAND", "TOR", "TURM", "TURMSTRAND",
        "PIER", "STRANDHAUS", "HAFEN", "MINE", "WALD",
    ]

    /// Häufigster Grasboden einer Insel.
    private mutating func groundBuilding(island: Int) -> BuildingType {
        if let ground = groundCache[island] { return ground }
        var counts: [Int: Int] = [:]
        for tile in world.islands[island].map.tiles.compactMap({ $0 }) where tile.building.kind == "BODEN" && tile.building.elevation > 0 {
            counts[tile.building.id, default: 0] += 1
        }
        let id = counts.max { $0.value < $1.value }?.key ?? 102
        let ground = buildings[id] ?? world.islands[island].map.tiles.compactMap({ $0 }).first!.building
        groundCache[island] = ground
        return ground
    }

    // MARK: Straßen

    /// Wählt für das Feld und seine Nachbarn die passende Straßenform (gerade, Kurve, T, Kreuzung).
    mutating func updateRoads(around x: Int, y: Int) {
        for (cx, cy) in [(x, y), (x, y - 1), (x + 1, y), (x, y + 1), (x - 1, y)] {
            guard let tile = world.tile(x: cx, y: cy), tile.building.kind == "STRASSE",
                let island = world.islandIndex(atX: cx, y: cy)
            else { continue }
            let (shape, rotation) = Self.roadShape(mask: roadMask(x: cx, y: cy))
            let family = tile.building.id / 10 * 10 + 1  // 401 Steinstraße, 411 Feldweg
            guard let road = buildings[family + shape] else { continue }
            let origin = world.islands[island]
            world.modifyIsland(island) { $0.place(road, x: cx - origin.x, y: cy - origin.y, rotation: rotation) }
        }
    }

    /// Nachbarn mit Straßenanschluss: Bit 0 = Nord (y−1), 1 = Ost (x+1), 2 = Süd, 3 = West.
    /// `planned` sind zusätzliche (geplante) Straßenfelder.
    func roadMask(x: Int, y: Int, planned: Set<Int> = []) -> Int {
        var mask = 0
        for (bit, (dx, dy)) in [(0, -1), (1, 0), (0, 1), (-1, 0)].enumerated() {
            let nx = x + dx
            let ny = y + dy
            if planned.contains(ny * world.width + nx) {
                mask |= 1 << bit
            } else if let kind = world.tile(x: nx, y: ny)?.building.kind, ["STRASSE", "BRUECKE", "PLATZ"].contains(kind) {
                mask |= 1 << bit
            }
        }
        return mask
    }

    /// Straßenformen für einen geplanten Weg (für die Bauvorschau), inklusive Anschluss an vorhandene Straßen.
    public func roadPreview(_ type: BuildingType, path: [(x: Int, y: Int)]) -> [(x: Int, y: Int, building: BuildingType, rotation: Int)] {
        let planned = Set(path.map { $0.y * world.width + $0.x })
        let family = type.id / 10 * 10 + 1
        return path.map { cell in
            let (shape, rotation) = Self.roadShape(mask: roadMask(x: cell.x, y: cell.y, planned: planned))
            return (cell.x, cell.y, buildings[family + shape] ?? type, rotation)
        }
    }

    /// Mittelpunkt und Radius des Einflussbereichs, den ein Gebäude an dieser Stelle hätte (nur Kontor).
    public func influencePreview(_ type: BuildingType, x: Int, y: Int, rotation: Int) -> (x: Float, y: Float, radius: Float)? {
        guard type.production == "KONTOR" else { return nil }
        let (w, h) = type.footprint(rotation: rotation)
        return (Float(x) + Float(w) / 2, Float(y) + Float(h) / 2, Float(type.radius ?? 0) > 0 ? Float(type.radius!) : Self.kontorRadius)
    }

    /// Form (0 = gerade, 1 = Kurve, 2 = T, 3 = Kreuzung) und Drehung je Anschlussmuster,
    /// abgeleitet aus den Straßen der besiedelten Originalinseln.
    static func roadShape(mask: Int) -> (shape: Int, rotation: Int) {
        switch mask {
        case 0b0101, 0b0001, 0b0100: (0, 1)  // Nord–Süd
        case 0b0011: (1, 0)  // N+O
        case 0b0110: (1, 1)  // O+S
        case 0b1100: (1, 2)  // S+W
        case 0b1001: (1, 3)  // N+W
        case 0b0111: (2, 0)  // ohne W
        case 0b1110: (2, 1)  // ohne N
        case 0b1101: (2, 2)  // ohne O
        case 0b1011: (2, 3)  // ohne S
        case 0b1111: (3, 0)
        default: (0, 0)  // Ost–West, einzeln
        }
    }
}
