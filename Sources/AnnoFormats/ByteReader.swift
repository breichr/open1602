/// Liest Little-Endian-Werte aus einem Byte-Array, mit Bounds-Checks.
struct ByteReader {
    let bytes: [UInt8]
    var position: Int

    init(_ bytes: [UInt8], position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    var remaining: Int { bytes.count - position }

    mutating func u8(_ context: @autoclosure () -> String) throws -> UInt8 {
        guard position < bytes.count else { throw FormatError.truncated(context: context()) }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func u32(_ context: @autoclosure () -> String) throws -> UInt32 {
        guard remaining >= 4 else { throw FormatError.truncated(context: context()) }
        defer { position += 4 }
        return UInt32(bytes[position])
            | UInt32(bytes[position + 1]) << 8
            | UInt32(bytes[position + 2]) << 16
            | UInt32(bytes[position + 3]) << 24
    }

    mutating func bytes(_ count: Int, _ context: @autoclosure () -> String) throws -> ArraySlice<UInt8> {
        guard count >= 0, remaining >= count else { throw FormatError.truncated(context: context()) }
        defer { position += count }
        return bytes[position..<position + count]
    }
}
