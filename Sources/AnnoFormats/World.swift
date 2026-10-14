/// Deterministischer Zufallsgenerator (SplitMix64), damit eine Welt mit gleichem Startwert gleich aussieht.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Eine Insel an ihrer Weltposition.
public struct PlacedIsland: Sendable {
    public let path: String
    public internal(set) var map: IslandMap
    public let x: Int
    public let y: Int
    public let climate: Climate
    public let hasNatives: Bool
    /// Hirsche aus `HIRSCH2` (Inselkoordinaten).
    public let deer: [(x: Int, y: Int)]

    public init(path: String, map: IslandMap, x: Int, y: Int, climate: Climate, hasNatives: Bool, deer: [(x: Int, y: Int)]) {
        self.path = path
        self.map = map
        self.x = x
        self.y = y
        self.climate = climate
        self.hasNatives = hasNatives
        self.deer = deer
    }
}

/// Weltkarte aus mehreren Inseln; alle übrigen Felder sind offenes Meer.
public struct WorldMap: Sendable, TileGrid {
    public let width: Int
    public let height: Int
    public private(set) var islands: [PlacedIsland]
    /// Inselindex je Feld (−1 = Meer).
    private let owner: [Int16]
    /// Offenes Meer in verschiedenen Animationsphasen.
    private let sea: [IslandTile]

    /// ID des offenen Meers in `haeuser.cod` (`IDMEER`).
    public static let openSeaID = 1201

    public init(width: Int, height: Int, islands: [PlacedIsland], buildings: BuildingTable) {
        self.width = width
        self.height = height
        self.islands = islands
        var owner = [Int16](repeating: -1, count: width * height)
        for (index, island) in islands.enumerated() {
            for y in 0..<island.map.height {
                for x in 0..<island.map.width {
                    let wx = island.x + x
                    let wy = island.y + y
                    guard wx >= 0, wy >= 0, wx < width, wy < height, island.map.tile(x: x, y: y) != nil else { continue }
                    owner[wy * width + wx] = Int16(index)
                }
            }
        }
        self.owner = owner
        if let water = buildings[Self.openSeaID] {
            sea = (0..<max(water.animationCount, 1)).map {
                IslandTile(building: water, fieldIndex: -1, rotation: 0, animation: $0, random: 0, dx: 0, dy: 0)
            }
        } else {
            sea = []
        }
    }

    public func tile(x: Int, y: Int) -> IslandTile? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = Int(owner[y * width + x])
        if index >= 0 {
            let island = islands[index]
            return island.map.tile(x: x - island.x, y: y - island.y)
        }
        // Phase aus der Position, damit das Meer nicht im Gleichtakt wogt.
        return sea.isEmpty ? nil : sea[(x &* 7 &+ y &* 13) % sea.count]
    }

    /// Insel an einer Weltposition.
    public func island(atX x: Int, y: Int) -> PlacedIsland? {
        islandIndex(atX: x, y: y).map { islands[$0] }
    }

    /// Index der Insel an einer Weltposition.
    public func islandIndex(atX x: Int, y: Int) -> Int? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = Int(owner[y * width + x])
        return index >= 0 ? index : nil
    }

    /// Ändert die Karte einer Insel (Bauen, Abreißen).
    public mutating func modifyIsland(_ index: Int, _ body: (inout IslandMap) -> Void) {
        body(&islands[index].map)
    }
}

extension WorldMap {
    /// Baut eine Weltvariante eines Szenarios mit zufällig gewählten Inselvorlagen.
    public static func generate(
        scenario: Scenario, worldIndex: Int, seed: UInt64, gameData: GameData, buildings: BuildingTable
    ) throws -> WorldMap {
        var rng = SeededRandom(seed: seed)
        let world = scenario.worlds[worldIndex % max(scenario.worlds.count, 1)]
        let files = gameData.allFiles

        // Basisvorlagen je Klima und Größe: `big07.scp`, nicht `big07s16.scp`/`big07b.scp`.
        func pool(_ climate: Climate, _ size: IslandSize) -> [String] {
            files.filter { path in
                let parts = path.split(separator: "/")
                guard parts.count == 2, parts[0].lowercased() == climate.templateDirectory.lowercased() else { return false }
                let name = parts[1].lowercased()
                guard name.hasPrefix(size.filePrefix), name.hasSuffix(".scp") else { return false }
                let digits = name.dropFirst(size.filePrefix.count).dropLast(4)
                return digits.count == 2 && digits.allSatisfy(\.isNumber)
            }
        }

        // Inselvorlagen wählen (möglichst ohne Wiederholung).
        var used = Set<String>()
        var chosen: [(slot: Scenario.IslandSlot, climate: Climate, path: String)] = []
        for slot in world.islands {
            let climate = slot.climate ?? (Bool.random(using: &rng) ? .north : .south)
            // Feste Vorlage; fehlt die Variante auf der CD, die unbesiedelte Basis gleicher Nummer.
            if let fixed = slot.templatePath,
                let path = [fixed, IslandFile.baseTemplatePath(for: fixed)].compactMap({ $0 }).first(where: { gameData.url(for: $0) != nil })
            {
                used.insert(path)
                chosen.append((slot, climate, path))
                continue
            }
            let candidates = pool(climate, slot.size)
            guard !candidates.isEmpty else { continue }
            let fresh = candidates.filter { !used.contains($0) }
            let path = (fresh.isEmpty ? candidates : fresh).randomElement(using: &rng)!
            used.insert(path)
            chosen.append((slot, climate, path))
        }

        // Eingeborene: passende Vorlagen durch ihre NAT-Fassung ersetzen.
        var native = Set<Int>()
        for (climate, count) in scenario.natives {
            let options = chosen.indices.filter { i in
                chosen[i].climate == climate && nativePath(for: chosen[i].path, climate: climate, gameData: gameData) != nil
            }.shuffled(using: &rng)
            native.formUnion(options.prefix(count))
        }

        var placed: [PlacedIsland] = []
        for (i, choice) in chosen.enumerated() {
            var template = try IslandFile(bytes: gameData.read(choice.path))
            var island = template
            var base: IslandFile? = nil
            var path = choice.path
            // Feste Varianten (`lit16b.scp`) liegen auf ihrer Basisvorlage.
            if let basePath = IslandFile.baseTemplatePath(for: choice.path), gameData.url(for: basePath) != nil {
                base = try IslandFile(bytes: gameData.read(basePath))
                template = base!
            }
            if native.contains(i), let natPath = nativePath(for: choice.path, climate: choice.climate, gameData: gameData) {
                island = try IslandFile(bytes: gameData.read(natPath))
                base = template
                path = natPath
            }
            placed.append(PlacedIsland(
                path: path, map: IslandMap(island: island, base: base, buildings: buildings),
                x: choice.slot.x, y: choice.slot.y, climate: choice.climate, hasNatives: native.contains(i),
                deer: island.deer.isEmpty ? template.deer : island.deer))
        }
        return WorldMap(width: scenario.width, height: scenario.height, islands: placed, buildings: buildings)
    }

    static func nativePath(for templatePath: String, climate: Climate, gameData: GameData) -> String? {
        guard let name = templatePath.split(separator: "/").last else { return nil }
        let path = "\(climate.nativeDirectory)/\(name)"
        return gameData.url(for: path) != nil ? path : nil
    }
}
