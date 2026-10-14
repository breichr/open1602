/// Kopf einer Insel (Chunk `INSEL3`, `INSEL4` oder `INSEL5`; die ersten Bytes sind gleich aufgebaut).
public struct IslandHeader: Sendable, Equatable {
    public let number: Int
    public let width: Int
    public let height: Int
    /// Position auf der Weltkarte (in Feldern).
    public let worldX: Int
    public let worldY: Int
    /// Unausgewertete Rohdaten des Kopfes.
    public let raw: [UInt8]
}

/// Ein Eintrag in `INSELHAUS`: ein Gebäude (auch Boden, Wald, Küste …) an seiner Ursprungsposition.
///
/// Aufbau (8 Byte): `UInt16` Gebäude-ID (= `Id − 20000` aus `haeuser.cod`), `UInt8` x, `UInt8` y,
/// `UInt32` Bitfeld: Drehung (2), Animationsschritt (4), unbekannt (8), Status (3), Zufall (5), Spieler (3).
public struct IslandField: Sendable, Equatable {
    public let buildingID: Int
    public let x: Int
    public let y: Int
    public let rotation: Int
    public let animation: Int
    public let status: Int
    public let random: Int
    public let player: Int
    public let rawFlags: UInt32

    public init(buildingID: Int, x: Int, y: Int, flags: UInt32) {
        self.buildingID = buildingID
        self.x = x
        self.y = y
        rawFlags = flags
        rotation = Int(flags & 0x3)
        animation = Int((flags >> 2) & 0xF)
        status = Int((flags >> 14) & 0x7)
        random = Int((flags >> 17) & 0x1F)
        player = Int((flags >> 22) & 0x7)
    }
}

/// Eine Insel aus einer `.scp`-Datei.
public struct IslandFile: Sendable {
    public let header: IslandHeader
    public let fields: [IslandField]
    /// Alle Chunks, auch die noch nicht ausgewerteten (`HIRSCH2`, `KONTOR2`, …).
    public let chunks: [Chunk]

    public init(bytes: [UInt8]) throws {
        chunks = try Chunk.readAll(bytes)
        guard let head = chunks.first(where: { ["INSEL3", "INSEL4", "INSEL5"].contains($0.name) }) else {
            throw FormatError.unexpectedChunk(expected: "INSEL3/4/5", found: chunks.first?.name ?? "")
        }
        var reader = ByteReader(head.data)
        let number = Int(try reader.u8("Inselkopf"))
        let width = Int(try reader.u8("Inselkopf"))
        let height = Int(try reader.u8("Inselkopf"))
        _ = try reader.u8("Inselkopf")
        let lo = try reader.bytes(4, "Inselkopf")
        header = IslandHeader(
            number: number, width: width, height: height,
            worldX: Int(lo[lo.startIndex]) | Int(lo[lo.startIndex + 1]) << 8,
            worldY: Int(lo[lo.startIndex + 2]) | Int(lo[lo.startIndex + 3]) << 8,
            raw: head.data)

        var fields: [IslandField] = []
        for chunk in chunks where chunk.name == "INSELHAUS" {
            var r = ByteReader(chunk.data)
            while r.remaining >= 8 {
                let id = Int(try r.u8("INSELHAUS")) | Int(try r.u8("INSELHAUS")) << 8
                let x = Int(try r.u8("INSELHAUS"))
                let y = Int(try r.u8("INSELHAUS"))
                fields.append(IslandField(buildingID: id, x: x, y: y, flags: try r.u32("INSELHAUS")))
            }
        }
        self.fields = fields
    }
}

extension IslandFile {
    /// Besiedelte Varianten (`big01s16.scp`, `big25b.scp`) enthalten nur Gebäude, das Gelände
    /// stammt aus der Basisvorlage (`big01.scp`, `big25.scp`). Liefert den Pfad der Basis oder `nil`.
    public static func baseTemplatePath(for path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let file = parts.last, file.lowercased().hasSuffix(".scp") else { return nil }
        let stem = Array(file.dropLast(4))
        // Präfix aus Buchstaben, zwei Ziffern, dann `sNN` oder genau ein Buchstabe.
        guard let firstDigit = stem.firstIndex(where: \.isNumber), firstDigit > 0,
            stem.count >= firstDigit + 3,
            stem[firstDigit].isNumber, stem[firstDigit + 1].isNumber
        else { return nil }
        let rest = stem[(firstDigit + 2)...]
        let isVariant =
            (rest.count == 1 && rest.first!.isLetter)
            || (rest.count == 3 && rest.first!.lowercased() == "s" && rest.dropFirst().allSatisfy(\.isNumber))
        guard isVariant else { return nil }
        let base = String(stem[..<(firstDigit + 2)]) + ".scp"
        return (parts.dropLast().map(String.init) + [base]).joined(separator: "/")
    }
}
