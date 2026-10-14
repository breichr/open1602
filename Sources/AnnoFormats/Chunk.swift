/// Ein Abschnitt im Chunk-Container, den BSH, COL, ZEI, SCP und Spielstände nutzen.
///
/// Aufbau: 16 Byte Name (nullterminiert, Rest beliebig), `UInt32` Länge, Nutzdaten.
public struct Chunk: Sendable {
    public let name: String
    public let data: [UInt8]

    public init(name: String, data: [UInt8]) {
        self.name = name
        self.data = data
    }

    static let headerSize = 20

    /// Liest alle Chunks einer Datei.
    public static func readAll(_ bytes: [UInt8]) throws -> [Chunk] {
        var reader = ByteReader(bytes)
        var chunks: [Chunk] = []
        while reader.remaining > 0 {
            let nameBytes = try reader.bytes(16, "Chunk-Name")
            let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
            let length = Int(try reader.u32("Länge von Chunk '\(name)'"))
            let data = try reader.bytes(length, "Daten von Chunk '\(name)'")
            chunks.append(Chunk(name: name, data: Array(data)))
        }
        return chunks
    }

    /// Liest eine Datei, die genau einen Chunk mit dem Namen `name` am Anfang enthält.
    public static func readFirst(_ bytes: [UInt8], named name: String) throws -> Chunk {
        guard let first = try readAll(bytes).first else {
            throw FormatError.truncated(context: "Chunk '\(name)'")
        }
        guard first.name == name else {
            throw FormatError.unexpectedChunk(expected: name, found: first.name)
        }
        return first
    }
}
