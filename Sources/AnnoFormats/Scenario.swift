/// Klimazone einer Insel.
public enum Climate: Int, Sendable, CaseIterable {
    case north = 0
    case south = 1

    /// Ordner der Inselvorlagen.
    public var templateDirectory: String { self == .north ? "Nord" : "Sued" }
    /// Ordner der Inseln mit Eingeborenen.
    public var nativeDirectory: String { self == .north ? "NORDNAT" : "SUEDNAT" }
}

/// Größenklassen der Inselvorlagen (Dateipräfix).
public enum IslandSize: Int, Sendable, CaseIterable {
    case little = 0, middle, medium, big, large

    public var filePrefix: String { ["lit", "mit", "med", "big", "large"][rawValue] }
}

/// Ein Szenario aus `Szenes/*.cod` (Endlosspiele und Zufallsszenarien).
///
/// Aufbau: Sammlung `SZENE` mit Feldern (`Name`, `Size`, `Money` …) und Unterobjekten
/// `SZENE_SHIP` (Startschiffe) und `SZENE_WELT` (mehrere Weltvarianten, getrennt durch `Nummer`).
public struct Scenario: Sendable {
    public struct Ship: Sendable, Equatable {
        public let player: Int
        /// Figur aus `figuren.cod`, z. B. `HANDEL1`.
        public let figure: String
        /// Blickrichtung 0…7 (0 = rechts oben, im Uhrzeigersinn).
        public let direction: Int
    }

    public struct IslandSlot: Sendable, Equatable {
        public let size: IslandSize
        public let x: Int
        public let y: Int
        /// `nil` = zufällig.
        public let climate: Climate?
        /// Feste Vorlage (`Insel: 0, 120,30, NORD, 16, "b"` → `Nord/lit16b.scp`), sonst zufällig.
        public let templateNumber: Int?
        public let templateVariant: String

        /// Pfad der festen Vorlage, falls angegeben.
        public var templatePath: String? {
            guard let number = templateNumber, let climate else { return nil }
            let digits = number < 10 ? "0\(number)" : "\(number)"
            return "\(climate.templateDirectory)/\(size.filePrefix)\(digits)\(templateVariant).scp"
        }
    }

    public struct World: Sendable {
        /// Startposition des Schiffs je Spieler.
        public var shipPositions: [Int: (x: Int, y: Int)] = [:]
        public var islands: [IslandSlot] = []
    }

    public let name: String
    public let width: Int
    public let height: Int
    public let money: Int
    public let ships: [Ship]
    public let worlds: [World]
    /// Anzahl Eingeborenen-Inseln je Klima.
    public let natives: [Climate: Int]
    /// Beschreibungstext (Zeilen).
    public let text: [String]
    /// Ladung der Startschiffe (je Schiff: Warenname aus `figuren.cod`/`haeuser.cod` → Menge).
    public let shipCargo: [[String: Int]]

    public init(document doc: CODDocument) throws {
        guard let scene = doc.items("SZENE").first else {
            throw FormatError.unexpectedChunk(expected: "SZENE", found: doc.collections.keys.sorted().joined(separator: ","))
        }
        name = scene["Name"]?.first?.stringValue ?? "Szenario"
        width = scene.int("Size", 0) ?? 500
        height = scene.int("Size", 1) ?? 350
        money = scene.int("Money") ?? 0
        text = scene.entries.filter { $0.key == "Text" }.compactMap { $0.values.last?.stringValue }

        var natives: [Climate: Int] = [:]
        for entry in scene.entries where entry.key == "Natives" {
            if let c = entry.values.first?.intValue.flatMap(Climate.init(rawValue:)), let n = entry.values.dropFirst().first?.intValue {
                natives[c, default: 0] += n
            }
        }
        self.natives = natives

        shipCargo = Self.groupEntries(scene.child("SZENE_SHIP")).map { entries in
            var cargo: [String: Int] = [:]
            for entry in entries where entry.key == "Ware" {
                if let name = entry.values.first?.symbol, let amount = entry.values.dropFirst().first?.intValue {
                    cargo[name, default: 0] += amount
                }
            }
            return cargo
        }
        ships = Self.groups(scene.child("SZENE_SHIP")).map { fields in
            Ship(
                player: fields["Playernr"]?.first?.intValue ?? 0,
                figure: fields["Figurnr"]?.first?.symbol ?? "HANDEL1",
                direction: fields["Ausricht"]?.first?.intValue ?? 0)
        }

        worlds = Self.groupEntries(scene.child("SZENE_WELT")).map { entries in
            var world = World()
            for (key, values) in entries {
                let ints = values.map(\.intValue)
                switch key {
                case "Shippos" where ints.count >= 3:
                    if let p = ints[0], let x = ints[1], let y = ints[2] { world.shipPositions[p] = (x, y) }
                case "Insel" where ints.count >= 3:
                    guard let s = ints[0].flatMap(IslandSize.init(rawValue:)), let x = ints[1], let y = ints[2] else { continue }
                    let climate = values.count > 3 ? values[3].intValue.flatMap(Climate.init(rawValue:)) : nil
                    let number = values.count > 4 ? values[4].intValue : nil
                    let variant = values.count > 5 ? values[5].stringValue ?? "" : ""
                    world.islands.append(IslandSlot(
                        size: s, x: x, y: y, climate: climate, templateNumber: number, templateVariant: variant))
                default:
                    break
                }
            }
            return world
        }
    }

    /// Zerlegt ein Unterobjekt mit mehreren `Nummer`-Abschnitten in Einträge je Abschnitt.
    static func groupEntries(_ object: CODObject?) -> [[(key: String, values: [CODValue])]] {
        guard let object else { return [] }
        var groups: [[(key: String, values: [CODValue])]] = []
        for entry in object.entries {
            if entry.key == "Nummer" || groups.isEmpty {
                groups.append([])
                if entry.key == "Nummer" { continue }
            }
            groups[groups.count - 1].append(entry)
        }
        return groups
    }

    /// Wie `groupEntries`, aber mit dem letzten Wert je Feld.
    static func groups(_ object: CODObject?) -> [[String: [CODValue]]] {
        groupEntries(object).map { entries in
            Dictionary(entries.map { ($0.key, $0.values) }, uniquingKeysWith: { _, last in last })
        }
    }
}
