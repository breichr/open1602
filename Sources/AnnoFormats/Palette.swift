public struct RGBColor: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// 256-Farben-Palette aus einer `.COL`-Datei (Chunk `COL`, 256 × RGBX).
public struct Palette: Sendable {
    public let colors: [RGBColor]

    public init(colors: [RGBColor]) {
        precondition(colors.count == 256, "Palette braucht 256 Farben")
        self.colors = colors
    }

    /// Liest eine komplette `.COL`-Datei.
    public init(colFile bytes: [UInt8]) throws {
        let chunk = try Chunk.readFirst(bytes, named: "COL")
        guard chunk.data.count == 1024 else {
            throw FormatError.invalidPalette(byteCount: chunk.data.count)
        }
        colors = (0..<256).map { i in
            RGBColor(r: chunk.data[i * 4], g: chunk.data[i * 4 + 1], b: chunk.data[i * 4 + 2])
        }
    }

    public subscript(index: UInt8) -> RGBColor { colors[Int(index)] }
}
