import AnnoFormats
import Foundation

let usage = """
    anno-tool – Werkzeuge für die Originaldaten von Anno 1602

    Benutzung:
      anno-tool info [--data DIR]
      anno-tool export-bsh (<datei> | --all) [--out DIR] [--palette DATEI] [--data DIR]

    Optionen:
      --data DIR       Spielordner (Standard: $OPEN1602_DATA, ./ANNO1602/ANNO1602 oder .)
      --out DIR        Zielordner für PNGs (Standard: ./export)
      --palette DATEI  Palette (Standard: ToolGfx/STADTFLD.COL im Spielordner)
      --all            alle BSH-Dateien des Spielordners exportieren

    <datei> ist ein Pfad oder relativ zum Spielordner (Groß-/Kleinschreibung egal),
    z. B. gfx/stadtfld.bsh.
    """

struct UsageError: Error, CustomStringConvertible {
    let description: String
}

/// Einfache Auswertung von `--option wert`, `--flag` und Positionsargumenten.
struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    static let valueOptions: Set<String> = ["--data", "--out", "--palette"]

    init(_ args: some Sequence<String>) throws {
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if Self.valueOptions.contains(arg) {
                guard let value = iterator.next() else { throw UsageError(description: "\(arg) braucht einen Wert") }
                options[arg] = value
            } else if arg.hasPrefix("--") {
                flags.insert(arg)
            } else {
                positional.append(arg)
            }
        }
    }
}

func info(_ args: Arguments) throws {
    let data = try GameData.locate(explicit: args.options["--data"])
    print("Spielordner: \(data.root.path)")
    let files = data.allFiles
    print("Dateien: \(files.count)")
    let byExtension = Dictionary(grouping: files) { ($0 as NSString).pathExtension.uppercased() }
    for (ext, list) in byExtension.sorted(by: { $0.value.count > $1.value.count }) {
        print("  \(ext.isEmpty ? "(ohne)" : ext): \(list.count)")
    }
    print("BSH-Dateien:")
    for path in data.files(withExtension: "bsh") {
        let archive = try BSHArchive(fileBytes: data.read(path))
        print("  \(path): \(archive.count) Bilder")
    }
}

func exportBSH(_ args: Arguments) throws {
    let all = args.flags.contains("--all")
    guard all != (args.positional.count == 1) else {
        throw UsageError(description: "Genau eine Datei oder --all angeben")
    }
    let gameData = try? GameData.locate(explicit: args.options["--data"])
    let outRoot = URL(fileURLWithPath: args.options["--out"] ?? "export")

    let palette: Palette
    if let palettePath = args.options["--palette"] {
        palette = try Palette(colFile: [UInt8](Data(contentsOf: URL(fileURLWithPath: palettePath))))
    } else if let gameData {
        palette = try Palette(colFile: gameData.read("ToolGfx/STADTFLD.COL"))
    } else {
        throw UsageError(description: "Kein Spielordner gefunden – --data oder --palette angeben")
    }

    // (Anzeigename, Bytes, Unterordner im Ziel)
    var sources: [(name: String, load: () throws -> [UInt8], target: String)] = []
    if all {
        guard let gameData else { throw UsageError(description: "--all braucht einen Spielordner (--data)") }
        for path in gameData.files(withExtension: "bsh") {
            sources.append((path, { try gameData.read(path) }, path))
        }
    } else {
        let arg = args.positional[0]
        if FileManager.default.fileExists(atPath: arg) {
            let url = URL(fileURLWithPath: arg)
            sources.append((arg, { [UInt8](try Data(contentsOf: url)) }, url.lastPathComponent))
        } else if let gameData, gameData.url(for: arg) != nil {
            sources.append((arg, { try gameData.read(arg) }, arg))
        } else {
            throw UsageError(description: "Datei '\(arg)' nicht gefunden")
        }
    }

    var totalImages = 0
    var totalEmpty = 0
    var failures: [String] = []
    for source in sources {
        let archive: BSHArchive
        do {
            archive = try BSHArchive(fileBytes: source.load())
        } catch {
            failures.append("\(source.name): \(error)")
            continue
        }
        let dir = outRoot.appendingPathComponent(source.target)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var empty = 0
        for i in 0..<archive.count {
            do {
                let image = try archive.image(at: i)
                guard image.width > 0, image.height > 0 else {
                    empty += 1
                    continue
                }
                try PNGWriter.write(
                    rgba: image.rgba(palette: palette),
                    width: image.width,
                    height: image.height,
                    to: dir.appendingPathComponent(String(format: "%05d.png", i))
                )
            } catch {
                failures.append("\(source.name) #\(i): \(error)")
            }
        }
        totalImages += archive.count
        totalEmpty += empty
        print("\(source.name): \(archive.count) Bilder\(empty > 0 ? " (\(empty) leer)" : "")")
    }
    print("Fertig: \(sources.count) Dateien, \(totalImages) Bilder, \(totalEmpty) leer, \(failures.count) Fehler → \(outRoot.path)")
    if !failures.isEmpty {
        for failure in failures.prefix(20) { print("  Fehler: \(failure)") }
        exit(1)
    }
}

let argv = CommandLine.arguments.dropFirst()
do {
    guard let command = argv.first else {
        print(usage)
        exit(0)
    }
    let args = try Arguments(argv.dropFirst())
    switch command {
    case "info": try info(args)
    case "export-bsh": try exportBSH(args)
    case "help", "-h", "--help": print(usage)
    default: throw UsageError(description: "Unbekannter Befehl '\(command)'")
    }
} catch let error as UsageError {
    FileHandle.standardError.write(Data("Fehler: \(error)\n\n\(usage)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("Fehler: \(error)\n".utf8))
    exit(1)
}
