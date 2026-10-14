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
}

/// Inselraster: jedes Feld kennt sein Gebäude (mehrfeldrige Gebäude belegen mehrere Felder).
public struct IslandMap: Sendable {
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

    public subscript(x: Int, y: Int) -> IslandTile? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return tiles[y * width + x]
    }
}
