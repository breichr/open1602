import AnnoFormats
import AnnoRender
import Metal

/// Draufsicht der Welt (ein Pixel je Feld) als palettenindiziertes Bild, plus ein weißes Pixel für Rahmen.
@MainActor
final class Minimap {
    private let device: MTLDevice
    private let palette: Palette
    private(set) var sheet: SpriteSheet?
    private var revision = -1
    /// Palettenindizes je Geländeart.
    private var colorCache: [String: UInt8] = [:]

    static let imageIndex = 0
    static let whiteIndex = 1
    static let blackIndex = 2

    init(device: MTLDevice, palette: Palette) {
        self.device = device
        self.palette = palette
    }

    /// Palettenindex, der einer Wunschfarbe am nächsten kommt.
    private func index(_ r: Int, _ g: Int, _ b: Int) -> UInt8 {
        var best = 0
        var bestDistance = Int.max
        for (i, c) in palette.colors.enumerated() {
            let d = (Int(c.r) - r) * (Int(c.r) - r) + (Int(c.g) - g) * (Int(c.g) - g) + (Int(c.b) - b) * (Int(c.b) - b)
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return UInt8(best)
    }

    private func color(for tile: IslandTile?) -> UInt8 {
        let kind = tile?.building.kind ?? "MEER"
        let key = tile?.building.elevation == 0 && !kind.hasPrefix("STRAND") ? (kind == "MEER" ? "MEER" : "FLACH") : kind
        if let cached = colorCache[key] { return cached }
        let value: UInt8 =
            switch key {
            case "MEER": index(24, 52, 110)
            case "FLACH": index(40, 100, 170)
            case "BODEN": index(70, 140, 40)
            case "WALD": index(30, 90, 30)
            case "FELS", "HANG", "HANGECK", "HANGQUELL": index(130, 125, 115)
            case "STRASSE", "PLATZ", "BRUECKE": index(150, 120, 80)
            case "GEBAEUDE", "HQ", "HAFEN", "PIER", "STRANDHAUS", "MINE", "TURM", "MAUER", "TOR": index(200, 60, 40)
            default: kind.hasPrefix("STRAND") ? index(190, 160, 100) : (kind.hasPrefix("FLUSS") ? index(60, 120, 200) : index(90, 130, 50))
            }
        colorCache[key] = value
        return value
    }

    /// Erzeugt das Bild neu, wenn sich die Welt geändert hat.
    func update(world: WorldMap, revision: Int) {
        guard revision != self.revision || sheet == nil else { return }
        self.revision = revision
        var image = IndexedImage(width: world.width, height: world.height, type: 1)
        image.opaque = Array(repeating: true, count: world.width * world.height)
        for y in 0..<world.height {
            for x in 0..<world.width {
                image.indices[y * world.width + x] = color(for: world.tile(x: x, y: y))
            }
        }
        var white = IndexedImage(width: 1, height: 1, type: 1)
        white.indices = [index(255, 255, 255)]
        white.opaque = [true]
        var black = IndexedImage(width: 1, height: 1, type: 1)
        black.indices = [index(20, 16, 12)]
        black.opaque = [true]
        sheet = try? SpriteSheet(device: device, images: [image, white, black], packer: AtlasPacker(pageSize: 1024))
    }
}
