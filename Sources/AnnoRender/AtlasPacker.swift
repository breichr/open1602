/// Position eines Bildes in einem Texturatlas.
public struct AtlasPlacement: Sendable, Equatable {
    public let page: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

/// Verteilt Bilder per Shelf-Packing auf quadratische Atlasseiten.
///
/// Bilder werden nach Höhe sortiert und zeilenweise („Regale“) einsortiert.
/// Für die Sprites von Anno 1602 (viele gleich hohe Kacheln) reicht das völlig.
public struct AtlasPacker: Sendable {
    public struct TooLarge: Error, CustomStringConvertible {
        public let index: Int
        public let width: Int
        public let height: Int
        public var description: String { "Bild \(index) (\(width)×\(height)) ist größer als eine Atlasseite" }
    }

    public struct Result: Sendable {
        /// In Eingabereihenfolge.
        public let placements: [AtlasPlacement]
        /// Genutzte Höhe je Seite (Seiten werden nicht voll allokiert).
        public let pageHeights: [Int]
        public var pageCount: Int { pageHeights.count }
    }

    public let pageSize: Int
    /// Abstand zwischen Bildern, damit beim Skalieren keine Nachbarpixel durchscheinen.
    public let padding: Int

    public init(pageSize: Int = 4096, padding: Int = 1) {
        self.pageSize = pageSize
        self.padding = padding
    }

    public func pack(sizes: [(width: Int, height: Int)]) throws -> Result {
        var placements = [AtlasPlacement?](repeating: nil, count: sizes.count)
        let order = sizes.indices.sorted { (sizes[$0].height, sizes[$0].width) > (sizes[$1].height, sizes[$1].width) }

        var pageHeights: [Int] = []
        var page = -1
        var x = 0
        var shelfY = 0
        var shelfHeight = 0

        for i in order {
            let (w, h) = sizes[i]
            if w == 0 || h == 0 {
                placements[i] = AtlasPlacement(page: max(page, 0), x: 0, y: 0, width: 0, height: 0)
                continue
            }
            guard w <= pageSize, h <= pageSize else { throw TooLarge(index: i, width: w, height: h) }
            if page < 0 {
                page = 0
                pageHeights.append(0)
            }
            if x + w > pageSize {
                shelfY += shelfHeight + padding
                x = 0
                shelfHeight = 0
            }
            if shelfY + h > pageSize {
                page += 1
                pageHeights.append(0)
                x = 0
                shelfY = 0
                shelfHeight = 0
            }
            placements[i] = AtlasPlacement(page: page, x: x, y: shelfY, width: w, height: h)
            x += w + padding
            shelfHeight = max(shelfHeight, h)
            pageHeights[page] = max(pageHeights[page], shelfY + h)
        }
        return Result(placements: placements.map { $0! }, pageHeights: pageHeights)
    }
}
