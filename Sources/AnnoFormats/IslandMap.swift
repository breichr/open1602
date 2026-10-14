/// Ein belegtes Inselfeld: welches Gebäude, welcher Teil davon.
public struct IslandTile: Sendable, Equatable {
    public let building: BuildingType
    /// Index in `IslandFile.fields`.
    public let fieldIndex: Int
    public let rotation: Int
    public let animation: Int
    public let random: Int
    /// Versatz innerhalb des gedrehten Grundrisses.
    public let dx: Int
    public let dy: Int

    /// Feld, an dem das Gebäude beginnt (Ursprungsecke des Grundrisses), relativ zu diesem Feld.
    public var originOffset: (dx: Int, dy: Int) { (-dx, -dy) }

    public init(building: BuildingType, fieldIndex: Int, rotation: Int, animation: Int, random: Int, dx: Int, dy: Int) {
        self.building = building
        self.fieldIndex = fieldIndex
        self.rotation = rotation
        self.animation = animation
        self.random = random
        self.dx = dx
        self.dy = dy
    }
}

/// Ein Raster aus Feldern, das gezeichnet werden kann (Insel oder ganze Welt).
public protocol TileGrid {
    var width: Int { get }
    var height: Int { get }
    func tile(x: Int, y: Int) -> IslandTile?
}

/// Inselraster: jedes Feld kennt sein Gebäude (mehrfeldrige Gebäude belegen mehrere Felder).
public struct IslandMap: Sendable, TileGrid {
    public let width: Int
    public let height: Int
    public private(set) var tiles: [IslandTile?]
    /// Gebäude-IDs aus der Datei, die es in `haeuser.cod` nicht gibt.
    public private(set) var unknownBuildingIDs: Set<Int> = []
    /// Felder, die von mehr als einem Gebäude belegt werden.
    public private(set) var overlaps = 0
    /// Gebäude, die über den Inselrand hinausragen.
    public private(set) var outOfBounds = 0

    /// - Parameter base: Basisvorlage, deren Gelände unter die Gebäude der Insel gelegt wird
    ///   (nur wenn die Größe übereinstimmt).
    public init(island: IslandFile, base: IslandFile? = nil, buildings: BuildingTable) {
        width = island.header.width
        height = island.header.height
        tiles = Array(repeating: nil, count: width * height)
        if let base, base.header.width == width, base.header.height == height {
            place(base.fields, buildings: buildings, countOverlaps: false)
        }
        place(island.fields, buildings: buildings, countOverlaps: true)
    }

    /// `true`, wenn jedes Feld belegt ist.
    public var isComplete: Bool { tiles.allSatisfy { $0 != nil } }

    private mutating func place(_ fields: [IslandField], buildings: BuildingTable, countOverlaps: Bool) {
        var placed = [Bool](repeating: false, count: width * height)
        for (index, field) in fields.enumerated() {
            guard let building = buildings[field.buildingID] else {
                unknownBuildingIDs.insert(field.buildingID)
                continue
            }
            let (w, h) = building.footprint(rotation: field.rotation)
            for dy in 0..<h {
                for dx in 0..<w {
                    let x = field.x + dx
                    let y = field.y + dy
                    guard x < width, y < height else {
                        outOfBounds += 1
                        continue
                    }
                    if countOverlaps && placed[y * width + x] { overlaps += 1 }
                    placed[y * width + x] = true
                    tiles[y * width + x] = IslandTile(
                        building: building, fieldIndex: index, rotation: field.rotation,
                        animation: field.animation, random: field.random, dx: dx, dy: dy)
                }
            }
        }
    }

    public subscript(x: Int, y: Int) -> IslandTile? { tile(x: x, y: y) }

    /// Setzt ein Gebäude mit Ursprungsecke `(x, y)`; überschreibt belegte Felder.
    public mutating func place(_ building: BuildingType, x: Int, y: Int, rotation: Int, animation: Int = 0) {
        let (w, h) = building.footprint(rotation: rotation)
        for dy in 0..<h {
            for dx in 0..<w where x + dx < width && y + dy < height && x + dx >= 0 && y + dy >= 0 {
                tiles[(y + dy) * width + x + dx] = IslandTile(
                    building: building, fieldIndex: -1, rotation: rotation, animation: animation, random: 0, dx: dx, dy: dy)
            }
        }
    }

    /// Ursprungsecke und Grundriss des Gebäudes auf Feld `(x, y)`.
    public func footprint(atX x: Int, y: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let tile = tile(x: x, y: y) else { return nil }
        let (w, h) = tile.building.footprint(rotation: tile.rotation)
        return (x - tile.dx, y - tile.dy, w, h)
    }

    public func tile(x: Int, y: Int) -> IslandTile? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return tiles[y * width + x]
    }
}
