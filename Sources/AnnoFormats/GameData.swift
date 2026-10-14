import Foundation

/// Zugriff auf den Spielordner der Originalversion (das Verzeichnis mit `haeuser.cod`).
///
/// Die Originaldaten mischen Schreibweisen (`STADTFLD.BSH`, `Stadtfld.bsh`, `Sgfx`),
/// daher werden Pfade ohne Rücksicht auf Groß-/Kleinschreibung aufgelöst.
public struct GameData: Sendable {
    public let root: URL
    /// Kleingeschriebener relativer Pfad (mit `/`) → tatsächliche Datei.
    private let index: [String: URL]

    /// Datei, an der ein gültiger Spielordner erkannt wird.
    public static let markerFile = "haeuser.cod"
    /// Umgebungsvariable für den Pfad zum Spielordner.
    public static let environmentKey = "OPEN1602_DATA"

    public enum Error: Swift.Error, CustomStringConvertible {
        case notAGameDirectory(URL)
        case fileNotFound(String)

        public var description: String {
            switch self {
            case .notAGameDirectory(let url):
                "'\(url.path)' ist kein Anno-1602-Spielordner (\(GameData.markerFile) fehlt)"
            case .fileNotFound(let path):
                "Datei '\(path)' nicht im Spielordner gefunden"
            }
        }
    }

    public init(root: URL) throws {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let index = Self.buildIndex(root: root), index[Self.markerFile] != nil else {
            throw Error.notAGameDirectory(root)
        }
        self.root = root
        self.index = index
    }

    /// Alle Dateien als relative Pfade in Originalschreibweise, sortiert.
    public var allFiles: [String] {
        index.values.map { relativePath(of: $0) }.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Relative Pfade aller Dateien mit der Endung `ext` (ohne Punkt, beliebige Schreibweise).
    public func files(withExtension ext: String) -> [String] {
        let suffix = "." + ext.lowercased()
        return allFiles.filter { $0.lowercased().hasSuffix(suffix) }
    }

    public func url(for relativePath: String) -> URL? {
        index[Self.normalize(relativePath)]
    }

    public func read(_ relativePath: String) throws -> [UInt8] {
        guard let url = url(for: relativePath) else { throw Error.fileNotFound(relativePath) }
        return [UInt8](try Data(contentsOf: url))
    }

    func relativePath(of url: URL) -> String {
        String(url.path.dropFirst(root.path.count).drop { $0 == "/" })
    }

    /// Sucht den Spielordner: expliziter Pfad, dann `OPEN1602_DATA`,
    /// dann `<cwd>/ANNO1602/ANNO1602`, dann `<cwd>` selbst.
    public static func locate(
        explicit: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> GameData {
        if let explicit {
            return try GameData(root: URL(fileURLWithPath: explicit))
        }
        if let env = environment[environmentKey], !env.isEmpty {
            return try GameData(root: URL(fileURLWithPath: env))
        }
        let candidates = [
            currentDirectory.appendingPathComponent("ANNO1602/ANNO1602"),
            currentDirectory,
        ]
        for candidate in candidates {
            if let data = try? GameData(root: candidate) { return data }
        }
        throw Error.notAGameDirectory(candidates[0])
    }

    private static func normalize(_ path: String) -> String {
        path.split(separator: "/").filter { !$0.isEmpty && $0 != "." }.joined(separator: "/").lowercased()
    }

    private static func buildIndex(root: URL) -> [String: URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var index: [String: URL] = [:]
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let relative = String(resolved.path.dropFirst(root.path.count).drop { $0 == "/" })
            index[normalize(relative)] = resolved
        }
        return index
    }
}
