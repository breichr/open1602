import AnnoFormats
import Metal

/// Mehrere BSH-Archive einer Zoomstufe in einem gemeinsamen Atlas, damit Gelände und Figuren
/// in einem Draw-Call (und damit in korrekter Tiefenreihenfolge) gezeichnet werden.
public final class SpriteLibrary {
    public let sheet: SpriteSheet
    /// Erster Index jedes Archivs im gemeinsamen Atlas (Schlüssel: Dateiname in Großbuchstaben ohne Endung).
    public let offsets: [String: Int]

    public init(device: MTLDevice, archives: [(name: String, archive: BSHArchive)]) throws {
        var images: [IndexedImage] = []
        var offsets: [String: Int] = [:]
        for (name, archive) in archives {
            offsets[name.uppercased()] = images.count
            for i in 0..<archive.count { images.append(try archive.image(at: i)) }
        }
        sheet = try SpriteSheet(device: device, images: images)
        self.offsets = offsets
    }

    /// Lädt beliebige Archive (`ZEI`-Fonts mit Chunk `ZEI`) aus dem Spielordner.
    public convenience init(device: MTLDevice, gameData: GameData, files: [(name: String, path: String)]) throws {
        let archives = try files.map { file in
            let chunk = file.path.lowercased().hasSuffix(".zei") ? "ZEI" : "BSH"
            return (file.name, try BSHArchive(fileBytes: gameData.read(file.path), chunkName: chunk))
        }
        try self.init(device: device, archives: archives)
    }

    /// Lädt `STADTFLD`, `SHIP`, `TIERE` … einer Zoomstufe aus dem Spielordner.
    public convenience init(device: MTLDevice, gameData: GameData, zoom: ZoomLevel, names: [String]) throws {
        let archives = try names.map { name in
            (name, try BSHArchive(fileBytes: gameData.read("\(zoom.directory)/\(name).BSH")))
        }
        try self.init(device: device, archives: archives)
    }

    public func index(_ archive: String, _ local: Int) -> Int { (offsets[archive.uppercased()] ?? 0) + local }

    public func size(of index: Int) -> (width: Int, height: Int)? {
        guard sheet.placements.indices.contains(index) else { return nil }
        let p = sheet.placements[index]
        return (p.width, p.height)
    }
}

extension SpriteLibrary {
    /// Text mit einer ZEI-Schrift (Zeichen 32…255, Latin-1). Liefert die Bilder und die Breite.
    public func text(
        _ string: String, font: String, at origin: SIMD2<Float>, spacing: Float = 0, tint: SIMD4<UInt8> = .zero
    ) -> (draws: [SpriteDraw], width: Float) {
        var x = origin.x
        var draws: [SpriteDraw] = []
        for scalar in string.unicodeScalars {
            let code = scalar.value <= 255 && scalar.value >= 32 ? Int(scalar.value) : Int(("?" as Unicode.Scalar).value)
            let index = self.index(font, code - 32)
            guard let size = size(of: index) else { continue }
            draws.append(SpriteDraw(index: index, position: SIMD2(x, origin.y), tint: tint))
            x += Float(size.width) + spacing
        }
        return (draws, x - origin.x)
    }
}
