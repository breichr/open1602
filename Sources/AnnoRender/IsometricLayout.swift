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

    /// Pixelmaße der Stufe GFX auf diese Stufe umrechnen (Höhen, Ankerpunkte).
    public func scaled(_ value: Int) -> Int { value >> rawValue }
    public func scaledElevation(_ elevation: Int) -> Int { scaled(elevation) }
}

/// Eine Figur (Schiff, Tier …), die zwischen den Kacheln in Tiefenreihenfolge gezeichnet wird.
public struct FigureSprite: Sendable {
    /// Position auf der Karte in Feldern (Feldmitte = x + 0.5).
    public var position: SIMD2<Float>
    /// Bildindex im Atlas.
    public var index: Int
    /// Punkt im Bild (in Pixeln dieser Zoomstufe), der auf dem Boden steht.
    public var anchor: SIMD2<Float>
    /// Zusätzliche Höhe in Pixeln dieser Zoomstufe (z. B. Inselniveau).
    public var elevation: Float

    public init(position: SIMD2<Float>, index: Int, anchor: SIMD2<Float>, elevation: Float = 0) {
        self.position = position
        self.index = index
        self.anchor = anchor
        self.elevation = elevation
    }
}

/// Isometrische Anordnung eines Feldrasters für eine Blickrichtung und Zoomstufe.
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

    /// Kontinuierliche Kartenposition → kontinuierliche Position im Bildschirmraster.
    public func screenPosition(ofMap p: SIMD2<Float>) -> SIMD2<Float> {
        let w = Float(mapWidth)
        let h = Float(mapHeight)
        switch rotation {
        case 0: return p
        case 1: return SIMD2(h - p.y, p.x)
        case 2: return SIMD2(w - p.x, h - p.y)
        default: return SIMD2(p.y, w - p.x)
        }
    }

    /// Umkehrung von `screenPosition(ofMap:)`.
    public func mapPosition(ofScreen s: SIMD2<Float>) -> SIMD2<Float> {
        let w = Float(mapWidth)
        let h = Float(mapHeight)
        switch rotation {
        case 0: return s
        case 1: return SIMD2(s.y, h - s.x)
        case 2: return SIMD2(w - s.x, h - s.y)
        default: return SIMD2(w - s.y, s.x)
        }
    }

    /// Bildschirmraster-Position → virtuelle Pixel (Bodenpunkt).
    public func pixel(ofScreen s: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2((s.x - s.y) * Float(zoom.tileWidth) / 2 + Float(zoom.tileWidth) / 2, (s.x + s.y) * Float(zoom.rowStep))
    }

    /// Virtuelle Pixel (Bodenpunkt) → Bildschirmraster-Position.
    public func screen(ofPixel p: SIMD2<Float>) -> SIMD2<Float> {
        let a = (p.x - Float(zoom.tileWidth) / 2) / (Float(zoom.tileWidth) / 2)  // sx − sy
        let b = p.y / Float(zoom.rowStep)  // sx + sy
        return SIMD2((a + b) / 2, (b - a) / 2)
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

    /// Bilder in Zeichenreihenfolge (hinten nach vorne) für den sichtbaren Ausschnitt.
    ///
    /// - Parameters:
    ///   - visible: Sichtbares Rechteck in virtuellen Pixeln (`nil` = alles).
    ///   - timeMs: Spielzeit für Animationen.
    ///   - figures: Figuren, die zwischen den Kacheln einsortiert werden.
    ///   - tileOffset: Erster Bildindex von `STADTFLD` im Atlas.
    ///   - spriteSize: Größe eines Bildes im Atlas.
    public func sprites(
        for grid: some TileGrid, visible: (min: SIMD2<Float>, max: SIMD2<Float>)? = nil, timeMs: Int = 0,
        figures: [FigureSprite] = [], tileOffset: Int = 0,
        spriteSize: (Int) -> (width: Int, height: Int)?
    ) -> [SpriteDraw] {
        let (gw, gh) = screenGrid
        let half = Float(zoom.tileWidth) / 2
        let step = Float(zoom.rowStep)
        // Reihen b = sx + sy und Spalten a = sx − sy, mit Rand für hohe Bilder.
        var aRange = -(gh - 1)...(gw - 1)
        var bRange = 0...(gw + gh - 2)
        if let visible {
            let margin = Float(zoom.scaled(320))
            let aMin = Int(((visible.min.x - Float(zoom.tileWidth)) / half).rounded(.down)) - 1
            let aMax = Int((visible.max.x / half).rounded(.up)) + 1
            let bMin = Int(((visible.min.y - Float(zoom.tileHeight)) / step).rounded(.down)) - 1
            let bMax = Int(((visible.max.y + margin) / step).rounded(.up)) + 1
            aRange = max(aRange.lowerBound, aMin)...max(min(aRange.upperBound, aMax), max(aRange.lowerBound, aMin))
            bRange = max(bRange.lowerBound, bMin)...max(min(bRange.upperBound, bMax), max(bRange.lowerBound, bMin))
        }

        // Figuren werden am Ende der Reihe gezeichnet, in der die Unterkante ihres Bildes liegt.
        // So übermalen flache Kacheln weiter vorn (z. B. Meer) keine Rümpfe, die über das eigene Feld hinausragen.
        var figuresByRow: [Int: [SpriteDraw]] = [:]
        for figure in figures {
            let s = screenPosition(ofMap: figure.position)
            let ground = pixel(ofScreen: s)
            let position = ground - figure.anchor - SIMD2(0, figure.elevation)
            let height = Float(spriteSize(figure.index)?.height ?? 0)
            let anchorRow = Int((s.x + s.y).rounded(.down))
            let bottomRow = Int(((position.y + height + figure.elevation) / step).rounded(.down)) - 1
            figuresByRow[max(anchorRow, bottomRow), default: []].append(SpriteDraw(index: figure.index, position: position))
        }

        var draws: [SpriteDraw] = []
        for b in bRange {
            // sx = (a + b) / 2 muss ganzzahlig sein → a hat dieselbe Parität wie b.
            var sx = max(0, b - (gh - 1), Int((Float(aRange.lowerBound + b) / 2).rounded(.up)))
            let sxMax = min(gw - 1, b, Int((Float(aRange.upperBound + b) / 2).rounded(.down)))
            while sx <= sxMax {
                let sy = b - sx
                let (x, y) = mapCell(screenX: sx, screenY: sy)
                if let tile = grid.tile(x: x, y: y) {
                    let index = tileOffset + spriteIndex(tile, timeMs: timeMs)
                    if let size = spriteSize(index) {
                        let origin = tileOrigin(screenX: sx, screenY: sy)
                        let elevation = Float(zoom.scaledElevation(tile.building.elevation))
                        draws.append(SpriteDraw(
                            index: index,
                            position: SIMD2(origin.x, origin.y + Float(zoom.tileHeight - size.height) - elevation)))
                    }
                }
                sx += 1
            }
            if let rowFigures = figuresByRow[b] { draws.append(contentsOf: rowFigures) }
        }
        return draws
    }

    /// Bildindex eines Feldes unter Berücksichtigung der Blickrichtung und Animation.
    public func spriteIndex(_ tile: IslandTile, timeMs: Int = 0) -> Int {
        let (fw, fh) = tile.building.footprint(rotation: tile.rotation)
        // Versatz im Grundriss so drehen wie das Raster.
        let (dx, dy): (Int, Int) =
            switch rotation {
            case 0: (tile.dx, tile.dy)
            case 1: (fh - 1 - tile.dy, tile.dx)
            case 2: (fw - 1 - tile.dx, fh - 1 - tile.dy)
            default: (tile.dy, fw - 1 - tile.dx)
            }
        var animation = tile.animation
        if let time = tile.building.animationTime { animation += timeMs / time }
        return tile.building.spriteIndex(rotation: tile.rotation + rotation, animation: animation, dx: dx, dy: dy)
    }
}
