/// Grafisch relevante Daten eines Gebäudetyps aus `haeuser.cod` (Sammlung `HAUS`).
///
/// „Gebäude“ umfasst alles, was auf einem Inselfeld steht: Boden, Wasser, Küste, Wald, Fels, Häuser.
public struct BuildingType: Sendable, Equatable {
    /// ID wie in Inseldateien (`Id − 20000`).
    public let id: Int
    public let number: Int
    /// Erstes Bild in `STADTFLD.BSH`.
    public let gfx: Int
    /// Art, z. B. `BODEN`, `MEER`, `WALD`, `FELS`.
    public let kind: String
    public let width: Int
    public let height: Int
    /// Anzahl Bilder je Drehrichtung (0 = nicht drehbar).
    public let rotateStride: Int
    public let animationCount: Int
    /// Bildabstand zwischen Animationsschritten.
    public let animationStride: Int
    /// Beim Bauen wird zufällig eine von `randomCount` Varianten gewählt (ID-Abstand `randomStride`),
    /// z. B. 11 Baumarten oder 7 Wohnhäuser. Für die Bildauswahl spielt das keine Rolle.
    public let randomCount: Int
    public let randomStride: Int
    /// Höhe über dem Meeresspiegel in Pixeln (Zoomstufe GFX).
    public let elevation: Int

    public init(
        id: Int, number: Int, gfx: Int, kind: String, width: Int, height: Int, rotateStride: Int,
        animationCount: Int, animationStride: Int, randomCount: Int, randomStride: Int, elevation: Int
    ) {
        self.id = id
        self.number = number
        self.gfx = gfx
        self.kind = kind
        self.width = width
        self.height = height
        self.rotateStride = rotateStride
        self.animationCount = animationCount
        self.animationStride = animationStride
        self.randomCount = randomCount
        self.randomStride = randomStride
        self.elevation = elevation
    }

    /// Größe des Grundrisses bei Drehung `rotation` (bei ungeraden Drehungen vertauscht).
    public func footprint(rotation: Int) -> (width: Int, height: Int) {
        rotation % 2 == 0 ? (width, height) : (height, width)
    }

    /// Bildindex in `STADTFLD.BSH` für das Feld `(dx, dy)` innerhalb des gedrehten Grundrisses.
    public func spriteIndex(rotation: Int, animation: Int, dx: Int, dy: Int) -> Int {
        let rotation = ((rotation % 4) + 4) % 4
        var index = gfx + rotation * rotateStride
        if animationCount > 0 { index += (animation % animationCount) * animationStride }
        // Teilbild: (dx, dy) zurück in die ungedrehte Anordnung (zeilenweise, Breite `width`) abbilden.
        let w = width
        let h = height
        switch rotation {
        case 0: index += dy * w + dx
        case 1: index += (h - dx - 1) * w + dy
        case 2: index += (h - dy - 1) * w + (w - dx - 1)
        default: index += dx * w + (w - dy - 1)
        }
        return index
    }
}

/// Alle Gebäudetypen aus `haeuser.cod`, nach Insel-ID.
public struct BuildingTable: Sendable {
    public let types: [Int: BuildingType]

    public init(types: [BuildingType]) {
        self.types = Dictionary(types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(cod: CODDocument) {
        var list: [BuildingType] = []
        for item in cod.items("HAUS") {
            guard let id = item.int("Id"), id >= 20000, let gfx = item.int("Gfx") else { continue }
            list.append(BuildingType(
                id: id - 20000,
                number: item.int("Nummer") ?? 0,
                gfx: gfx,
                kind: item.symbol("Kind") ?? "UNUSED",
                width: max(item.int("Size", 0) ?? 1, 1),
                height: max(item.int("Size", 1) ?? 1, 1),
                rotateStride: item.int("Rotate") ?? 0,
                animationCount: item.int("AnimAnz") ?? 0,
                animationStride: item.int("AnimAdd") ?? 0,
                randomCount: item.int("RandAnz") ?? 1,
                randomStride: item.int("RandAdd") ?? 0,
                elevation: item.int("Posoffs") ?? 0))
        }
        self.init(types: list)
    }

    /// Liest `haeuser.cod` aus dem Spielordner.
    public init(gameData: GameData) throws {
        self.init(cod: COD.parse(encrypted: try gameData.read("haeuser.cod")))
    }

    public subscript(id: Int) -> BuildingType? { types[id] }
}
