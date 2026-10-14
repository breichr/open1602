/// Fehler beim Lesen der Originaldateien.
public enum FormatError: Error, Equatable, CustomStringConvertible {
    /// Die Daten enden, bevor `context` vollständig gelesen wurde.
    case truncated(context: String)
    /// Ein Chunk mit unerwartetem Namen wurde gefunden.
    case unexpectedChunk(expected: String, found: String)
    /// Ein Offset zeigt außerhalb der Daten.
    case invalidOffset(index: Int, offset: Int)
    /// RLE-Daten schreiben über den Bildrand hinaus.
    case rleOverflow(image: Int)
    /// Die Palette hat nicht 256 Einträge.
    case invalidPalette(byteCount: Int)

    public var description: String {
        switch self {
        case .truncated(let context):
            "Daten abgeschnitten: \(context)"
        case .unexpectedChunk(let expected, let found):
            "Chunk '\(expected)' erwartet, '\(found)' gefunden"
        case .invalidOffset(let index, let offset):
            "Ungültiger Offset \(offset) für Eintrag \(index)"
        case .rleOverflow(let image):
            "RLE-Daten von Bild \(image) überschreiten die Bildgröße"
        case .invalidPalette(let byteCount):
            "Palette mit \(byteCount) Bytes statt 1024"
        }
    }
}
