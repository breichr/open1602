import AnnoFormats

/// Die drei Zoomstufen des Originals. Alle nutzen dieselben Bildindizes in `STADTFLD.BSH`.
public enum ZoomLevel: Int, CaseIterable, Sendable {
    /// `GFX/` – Kacheln 64×31
    case large = 0
    /// `MGFX/` – Kacheln 32×15
    case medium = 1
    /// `SGFX/` – Kacheln 16×7
    case small = 2

    public var directory: String {
        switch self {
        case .large: "GFX"
        case .medium: "MGFX"
        case .small: "SGFX"
        }
    }

    public var tileWidth: Int { 64 >> rawValue }
    public var tileHeight: Int { (32 >> rawValue) - 1 }
    /// Vertikaler Abstand zweier Kachelreihen (halbe Kachelhöhe).
    public var rowStep: Int { 16 >> rawValue }

    /// Gebäudehöhen (`Posoffs`) gelten für GFX und werden pro Stufe halbiert.
    public func scaledElevation(_ elevation: Int) -> Int { elevation >> rawValue }
}

/// Isometrische Anordnung einer Insel für eine Blickrichtung und Zoomstufe.
public struct IsometricLayout: Sendable {
    public let zoom: ZoomLevel
    /// Blickrichtung in Vierteldrehungen (0…3).
    public let rotation: Int
    public let mapWidth: Int
    public let mapHeight: Int

    public init(mapWidth: Int, mapHeight: Int, rotation: Int, zoom: ZoomLevel) {
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
        self.rotation = ((rotation % 4) + 4) % 4
        self.zoom = zoom
    }

    /// Größe des Rasters in Bildschirmrichtung.
    public var screenGrid: (width: Int, height: Int) {
        rotation % 2 == 0 ? (mapWidth, mapHeight) : (mapHeight, mapWidth)
    }

    /// Kartenfeld → Feld im gedrehten Bildschirmraster.
    public func screenCell(x: Int, y: Int) -> (x: Int, y: Int) {
        switch rotation {
        case 0: (x, y)
        case 1: (mapHeight - 1 - y, x)
        case 2: (mapWidth - 1 - x, mapHeight - 1 - y)
        default: (y, mapWidth - 1 - x)
        }
    }

    /// Feld im Bildschirmraster → Kartenfeld.
    public func mapCell(screenX sx: Int, screenY sy: Int) -> (x: Int, y: Int) {
        switch rotation {
        case 0: (sx, sy)
        case 1: (sy, mapHeight - 1 - sx)
        case 2: (mapWidth - 1 - sx, mapHeight - 1 - sy)
        default: (mapWidth - 1 - sy, sx)
        }
    }

    /// Linke obere Ecke der Bodenkachel eines Bildschirmfelds (virtuelle Pixel).
    public func tileOrigin(screenX sx: Int, screenY sy: Int) -> SIMD2<Float> {
        SIMD2(Float((sx - sy) * zoom.tileWidth / 2), Float((sx + sy) * zoom.rowStep))
    }

    /// Begrenzungsrechteck der Bodenkacheln (ohne hohe Gebäude).
    public var groundBounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        let (w, h) = screenGrid
        let minX = Float(-(h - 1) * zoom.tileWidth / 2)
        let maxX = Float((w - 1) * zoom.tileWidth / 2 + zoom.tileWidth)
        let maxY = Float((w + h - 2) * zoom.rowStep + zoom.tileHeight)
        return (SIMD2(minX, 0), SIMD2(maxX, maxY))
    }

    /// Bild und Position für jedes belegte Feld, in Zeichenreihenfolge (hinten nach vorne).
    ///
    /// - Parameter spriteSize: Größe eines Bildes der aktuellen Zoomstufe.
    public func sprites(for map: IslandMap, spriteSize: (Int) -> (width: Int, height: Int)?) -> [SpriteDraw] {
        let (gw, gh) = screenGrid
        var draws: [SpriteDraw] = []
        draws.reserveCapacity(map.width * map.height)
        for s in 0..<(gw + gh - 1) {
            for sx in max(0, s - gh + 1)...min(s, gw - 1) {
                let sy = s - sx
                let (x, y) = mapCell(screenX: sx, screenY: sy)
                guard let tile = map[x, y] else { continue }
                let index = spriteIndex(tile)
                guard let size = spriteSize(index) else { continue }
                let origin = tileOrigin(screenX: sx, screenY: sy)
                let elevation = Float(zoom.scaledElevation(tile.building.elevation))
                let position = SIMD2(origin.x, origin.y + Float(zoom.tileHeight - size.height) - elevation)
                draws.append(SpriteDraw(index: index, position: position))
            }
        }
        return draws
    }

    /// Bildindex eines Feldes unter Berücksichtigung der Blickrichtung.
    public func spriteIndex(_ tile: IslandTile) -> Int {
        let (fw, fh) = tile.building.footprint(rotation: tile.rotation)
        // Versatz im Grundriss so drehen wie das Raster.
        let (dx, dy): (Int, Int) =
            switch rotation {
            case 0: (tile.dx, tile.dy)
            case 1: (fh - 1 - tile.dy, tile.dx)
            case 2: (fw - 1 - tile.dx, fh - 1 - tile.dy)
            default: (tile.dy, fw - 1 - tile.dx)
            }
        return tile.building.spriteIndex(
            rotation: tile.rotation + rotation, animation: tile.animation, dx: dx, dy: dy)
    }
}
