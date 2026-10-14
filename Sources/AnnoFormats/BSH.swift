/// Ein palettenbasiertes Bild mit Transparenz.
public struct IndexedImage: Sendable {
    public let width: Int
    public let height: Int
    /// Bildtyp aus dem Header (bisher immer 1 beobachtet).
    public let type: UInt32
    /// Palettenindex je Pixel, zeilenweise.
    public var indices: [UInt8]
    /// `false` für transparente Pixel. Getrennt gespeichert, weil Index 0 eine echte Farbe ist.
    public var opaque: [Bool]

    public init(width: Int, height: Int, type: UInt32) {
        self.width = width
        self.height = height
        self.type = type
        indices = Array(repeating: 0, count: width * height)
        opaque = Array(repeating: false, count: width * height)
    }

    /// RGBA-Pixel (nicht vormultipliziert), transparente Pixel sind (0, 0, 0, 0).
    public func rgba(palette: Palette) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<indices.count where opaque[i] {
            let c = palette[indices[i]]
            out[i * 4] = c.r
            out[i * 4 + 1] = c.g
            out[i * 4 + 2] = c.b
            out[i * 4 + 3] = 255
        }
        return out
    }
}

/// Header eines Bildes in einem BSH-Archiv.
public struct BSHImageHeader: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let type: UInt32
    public let length: Int
}

/// Sprite-Archiv (`.BSH`; `.ZEI`-Fonts nutzen denselben Aufbau mit Chunk `ZEI`).
///
/// Nutzdaten: `UInt32`-Offsettabelle (Anzahl = erster Offset / 4), dann je Bild
/// `width, height, type, length` (je `UInt32`) und RLE-Daten.
/// Bilder werden erst bei Zugriff dekodiert.
public struct BSHArchive: Sendable {
    public let chunkName: String
    let payload: [UInt8]
    public let offsets: [Int]

    public var count: Int { offsets.count }

    public init(fileBytes: [UInt8], chunkName: String = "BSH") throws {
        let chunk = try Chunk.readFirst(fileBytes, named: chunkName)
        try self.init(payload: chunk.data, chunkName: chunkName)
    }

    init(payload: [UInt8], chunkName: String) throws {
        self.chunkName = chunkName
        self.payload = payload
        var reader = ByteReader(payload)
        guard reader.remaining > 0 else {
            offsets = []
            return
        }
        let first = Int(try reader.u32("Offsettabelle"))
        guard first % 4 == 0, first >= 4, first <= payload.count else {
            throw FormatError.invalidOffset(index: 0, offset: first)
        }
        var offsets = [first]
        for i in 1..<(first / 4) {
            let offset = Int(try reader.u32("Offsettabelle"))
            guard offset + 16 <= payload.count else {
                throw FormatError.invalidOffset(index: i, offset: offset)
            }
            offsets.append(offset)
        }
        self.offsets = offsets
    }

    public func header(at index: Int) throws -> BSHImageHeader {
        var reader = ByteReader(payload, position: offsets[index])
        return BSHImageHeader(
            width: Int(try reader.u32("Bild \(index)")),
            height: Int(try reader.u32("Bild \(index)")),
            type: try reader.u32("Bild \(index)"),
            length: Int(try reader.u32("Bild \(index)"))
        )
    }

    public func image(at index: Int) throws -> IndexedImage {
        var header = try header(at: index)
        // Schriftzeichen (`ZEI`) ragen für Unterschneidungen über ihre Laufweite hinaus: Bild verbreitern.
        if chunkName == "ZEI" {
            let extent = try measure(index)
            header = BSHImageHeader(
                width: max(header.width, extent.width), height: max(header.height, extent.height), type: header.type,
                length: header.length)
        }
        var image = IndexedImage(width: header.width, height: header.height, type: header.type)
        var reader = ByteReader(payload, position: offsets[index] + 16)
        var x = 0
        var y = 0
        while true {
            let code = try reader.u8("RLE von Bild \(index)")
            if code == 0xFF { break }
            if code == 0xFE {
                x = 0
                y += 1
                continue
            }
            x += Int(code)
            let count = Int(try reader.u8("RLE von Bild \(index)"))
            let pixels = try reader.bytes(count, "RLE von Bild \(index)")
            guard y < header.height, x + count <= header.width else {
                throw FormatError.rleOverflow(image: index)
            }
            let start = y * header.width + x
            image.indices.replaceSubrange(start..<start + count, with: pixels)
            for i in start..<start + count { image.opaque[i] = true }
            x += count
        }
        return image
    }

    /// Tatsächlich beschriebene Fläche eines Bildes.
    private func measure(_ index: Int) throws -> (width: Int, height: Int) {
        var reader = ByteReader(payload, position: offsets[index] + 16)
        var x = 0
        var y = 0
        var maxX = 0
        var maxY = 0
        while true {
            let code = try reader.u8("RLE von Bild \(index)")
            if code == 0xFF { break }
            if code == 0xFE {
                x = 0
                y += 1
                continue
            }
            x += Int(code)
            let count = Int(try reader.u8("RLE von Bild \(index)"))
            _ = try reader.bytes(count, "RLE von Bild \(index)")
            x += count
            maxX = max(maxX, x)
            maxY = max(maxY, y + 1)
        }
        return (maxX, maxY)
    }
}
