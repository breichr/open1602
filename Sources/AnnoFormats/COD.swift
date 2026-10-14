import Foundation

/// Skriptdateien von Anno 1602 (`haeuser.cod`, `figuren.cod`, `Szenes/*.cod`, `*.GAD`).
///
/// `.cod`-Dateien sind verschlüsselt: jedes Byte ist negiert. `.GAD` ist Klartext mit derselben Grammatik.
///
/// Grammatik (zeilenweise, `;` leitet Kommentare ein):
/// - `NAME = Ausdruck` – Variable/Konstante. Ausdrücke dürfen Felder des aktuellen Eintrags nennen (`HAUSWACHS = Nummer`).
/// - `Objekt: NAME` … `EndObj;` – auf oberster Ebene eine Sammlung (z. B. `HAUS`), sonst ein Unterobjekt des aktuellen Eintrags.
/// - `Feld: Wert, Wert, …` – Feld setzen. `Nummer:` beginnt einen neuen Eintrag der Sammlung.
/// - `@Feld: +n` / `@Feld: -n` – relativ zum vorherigen Eintrag (ohne Vorzeichen: absolut).
/// - `ObjFill: von, bis` – den aktuellen Eintrag als Vorlage für die Nummern `von…bis` verwenden.
/// - `ObjFill: n` – alle Felder des Eintrags `n` in den aktuellen Eintrag kopieren.
public enum COD {
    /// Entschlüsselt `.cod`-Bytes (`b → −b`) und dekodiert Latin-1.
    public static func decrypt(_ bytes: [UInt8]) -> String {
        decodeLatin1(bytes.map { 0 &- $0 })
    }

    public static func decodeLatin1(_ bytes: [UInt8]) -> String {
        String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    /// Liest eine verschlüsselte `.cod`-Datei.
    public static func parse(encrypted bytes: [UInt8]) -> CODDocument {
        parse(text: decrypt(bytes))
    }

    public static func parse(text: String) -> CODDocument {
        var parser = CODParser()
        for (number, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            parser.parse(line: String(line), number: number + 1)
        }
        return parser.finish()
    }
}

/// Ein Wert in einem COD-Feld.
public enum CODValue: Sendable, Equatable, CustomStringConvertible {
    case int(Int)
    case float(Double)
    /// Unaufgelöster Bezeichner, z. B. `BODEN` oder `WAV_STANDARD`.
    case symbol(String)
    /// Text in Anführungszeichen.
    case string(String)

    public var intValue: Int? {
        switch self {
        case .int(let v): v
        case .float(let v): Int(v)
        case .symbol, .string: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let v): Double(v)
        case .float(let v): v
        case .symbol, .string: nil
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { s } else { nil }
    }

    public var symbol: String? {
        if case .symbol(let s) = self { s } else { nil }
    }

    public var description: String {
        switch self {
        case .int(let v): "\(v)"
        case .float(let v): "\(v)"
        case .symbol(let s): s
        case .string(let s): "\"\(s)\""
        }
    }
}

/// Ein Objekt: Felder plus benannte Unterobjekte.
public struct CODObject: Sendable, Equatable {
    /// Letzter gesetzter Wert je Feld.
    public var fields: [String: [CODValue]] = [:]
    /// Alle Zuweisungen in Reihenfolge (für mehrfach vorkommende Felder wie `Ware:`).
    public var entries: [(key: String, values: [CODValue])] = []
    public var children: [String: [CODObject]] = [:]

    public init() {}

    public subscript(field: String) -> [CODValue]? { fields[field] }

    public func int(_ field: String, _ index: Int = 0) -> Int? {
        fields[field].flatMap { $0.indices.contains(index) ? $0[index].intValue : nil }
    }

    public func symbol(_ field: String, _ index: Int = 0) -> String? {
        fields[field].flatMap { $0.indices.contains(index) ? $0[index].symbol : nil }
    }

    public func child(_ name: String) -> CODObject? { children[name]?.first }

    mutating func set(_ key: String, _ values: [CODValue]) {
        fields[key] = values
        entries.append((key, values))
    }

    public static func == (lhs: CODObject, rhs: CODObject) -> Bool {
        lhs.fields == rhs.fields && lhs.children == rhs.children
            && lhs.entries.map(\.key) == rhs.entries.map(\.key) && lhs.entries.map(\.values) == rhs.entries.map(\.values)
    }
}

/// Ergebnis des Parsens: Variablen und Sammlungen (z. B. `HAUS`) mit Einträgen nach `Nummer`.
public struct CODDocument: Sendable {
    public var variables: [String: CODValue]
    /// Sammlung → Einträge in Reihenfolge ihrer `Nummer`.
    public var collections: [String: [Int: CODObject]]
    /// Sammlungen ohne `Nummer` (z. B. einzelne Konfigurationsobjekte).
    public var singletons: [String: [CODObject]]
    /// Zeilen, die nicht verstanden wurden (Zeilennummer, Inhalt).
    public var unparsedLines: [(line: Int, text: String)]

    public func items(_ collection: String) -> [CODObject] {
        (collections[collection] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
    }
}

struct CODParser {
    private var variables: [String: CODValue] = [:]
    private var collections: [String: [Int: CODObject]] = [:]
    private var singletons: [String: [CODObject]] = [:]
    private var unparsed: [(Int, String)] = []

    /// Name der offenen Sammlung auf oberster Ebene.
    private var collection: String?
    /// Aktueller Eintrag (noch nicht in `collections` zurückgeschrieben).
    private var current: CODObject?
    private var currentNumber: Int?
    /// Zuletzt abgeschlossener Eintrag, Basis für `@Feld: +n`.
    private var previous: CODObject?
    /// Pfad offener Unterobjekte im aktuellen Eintrag.
    private var childPath: [String] = []
    /// Objekt ohne `Nummer` (Sammlung ohne Einträge).
    private var singleton: CODObject?
    /// Vorlage aus `ObjFill: von, bis` für neue Einträge der Sammlung.
    private var templates: [String: CODObject] = [:]

    mutating func parse(line raw: String, number: Int) {
        let line = Self.stripComment(raw).trimmingCharacters(in: .whitespaces)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("EndObj") {
            endObject()
            return
        }
        guard !line.isEmpty else { return }

        if let colon = line.firstIndex(of: ":") {
            var key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let valueText = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let relative = key.hasPrefix("@")
            if relative { key.removeFirst() }
            guard isIdentifier(key) else { return fail(number, raw) }
            handleField(key, valueText: valueText, relative: relative, line: number, raw: raw)
        } else if let equals = line.firstIndex(of: "=") {
            var name = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            // `@NAME = +n` erhöht eine Variable relativ zu ihrem bisherigen Wert.
            let relative = name.hasPrefix("@")
            if relative { name.removeFirst() }
            let base = relative ? variables[name]?.intValue ?? 0 : nil
            guard isIdentifier(name), let value = evaluate(String(line[line.index(after: equals)...]), relativeTo: base) else {
                return fail(number, raw)
            }
            variables[name] = value
        } else {
            fail(number, raw)
        }
    }

    /// Entfernt alles ab `;`, außer innerhalb von Anführungszeichen.
    static func stripComment(_ raw: String) -> String {
        var quoted = false
        for (i, ch) in zip(raw.indices, raw) {
            if ch == "\"" { quoted.toggle() }
            if ch == ";" && !quoted { return String(raw[..<i]) }
        }
        return raw
    }

    private mutating func handleField(_ key: String, valueText: String, relative: Bool, line: Int, raw: String) {
        switch key {
        case "Objekt":
            beginObject(valueText)
        case "Nummer" where childPath.isEmpty && collection != nil:
            let base = currentNumber ?? previousNumber
            switch evaluate(valueText, relativeTo: relative ? base : nil) {
            case .int(let value)?:
                beginItem(value)
            case .symbol(let name)?:
                // Symbolische Nummern (z. B. `INFRA_WIRT`) sind im Original Konstanten des Programms.
                // Sie bekommen fortlaufende Nummern und werden als Variable bekannt gemacht.
                let value = (base ?? -1) + 1
                variables[name] = .int(value)
                beginItem(value)
            default:
                fail(line, raw)
            }
        case "ObjFill" where childPath.isEmpty:
            objFill(splitValues(valueText).map { evaluate($0) })
        default:
            let parts = splitValues(valueText)
            var values: [CODValue] = []
            for (i, part) in parts.enumerated() {
                let base = relative ? previousValue(key, index: i) : nil
                guard let value = evaluate(part, relativeTo: base) else { return fail(line, raw) }
                values.append(value)
            }
            setField(key, values)
        }
    }

    // MARK: Objekte

    private mutating func beginObject(_ name: String) {
        if collection == nil {
            collection = name
            current = nil
            currentNumber = nil
            previous = nil
            singleton = CODObject()
        } else if current != nil || singleton != nil {
            childPath.append(name)
            mutateTarget(createChild: true) { _ in }
        }
    }

    private mutating func endObject() {
        if !childPath.isEmpty {
            childPath.removeLast()
            return
        }
        commitItem()
        if let name = collection, let singleton, !singleton.fields.isEmpty || !singleton.children.isEmpty {
            singletons[name, default: []].append(singleton)
        }
        collection = nil
        singleton = nil
        current = nil
        currentNumber = nil
        previous = nil
    }

    private mutating func beginItem(_ number: Int) {
        commitItem()
        current = collections[collection!]?[number] ?? templates[collection!] ?? CODObject()
        currentNumber = number
        current!.fields["Nummer"] = [.int(number)]
        singleton = nil
    }

    private mutating func commitItem() {
        guard let name = collection, let current, let currentNumber else { return }
        collections[name, default: [:]][currentNumber] = current
        previous = current
        self.current = nil
    }

    private var previousNumber: Int? { previous?.int("Nummer") }

    /// `ObjFill: von, bis` macht den aktuellen Eintrag zur Vorlage (das Ende ist oft eine Programmkonstante
    /// wie `MAXHAUS`), `ObjFill: n` kopiert Eintrag `n` in den aktuellen.
    private mutating func objFill(_ values: [CODValue?]) {
        guard let name = collection, let current else { return }
        if values.count >= 2 {
            var template = current
            template.fields["Nummer"] = nil
            template.entries.removeAll { $0.key == "Nummer" }
            templates[name] = template
        } else if let source = values.first??.intValue, let template = collections[name]?[source] {
            var copy = template
            copy.fields["Nummer"] = current.fields["Nummer"]
            self.current = copy
        }
    }

    private func previousValue(_ key: String, index: Int) -> Int? {
        var object = previous
        for name in childPath { object = object?.child(name) }
        guard let values = object?.fields[key], values.indices.contains(index) else {
            // Auch der aktuelle Eintrag kann die Basis sein (z. B. aus einer Vorlage).
            var cur = current
            for name in childPath { cur = cur?.child(name) }
            return cur?.int(key, index)
        }
        return values[index].intValue
    }

    private mutating func setField(_ key: String, _ values: [CODValue]) {
        if current == nil && singleton == nil {
            // Felder außerhalb von Objekten (z. B. am Dateianfang) werden wie Variablen behandelt.
            if values.count == 1 { variables[key] = values[0] }
            return
        }
        mutateTarget(createChild: false) { $0.set(key, values) }
    }

    /// Wendet `body` auf das innerste offene Objekt an.
    private mutating func mutateTarget(createChild: Bool, _ body: (inout CODObject) -> Void) {
        func descend(_ object: inout CODObject, _ path: ArraySlice<String>) {
            guard let name = path.first else { return body(&object) }
            if object.children[name]?.isEmpty ?? true {
                object.children[name] = [CODObject()]
            }
            descend(&object.children[name]![0], path.dropFirst())
        }
        if current != nil {
            descend(&current!, childPath[...])
        } else if singleton != nil {
            descend(&singleton!, childPath[...])
        }
    }

    // MARK: Ausdrücke

    /// Trennt an Kommas außerhalb von Anführungszeichen.
    private func splitValues(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quoted = false
        for ch in text {
            if ch == "\"" { quoted.toggle() }
            if ch == "," && !quoted {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Wertet `a + b - c` aus. Mit `relativeTo` wird ein führendes Vorzeichen auf die Basis addiert.
    private func evaluate(_ text: String, relativeTo base: Int? = nil) -> CODValue? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("\"") {
            return .string(String(text.dropFirst().prefix { $0 != "\"" }))
        }
        // Flags (`INFRA_WIRT | INFRA_ARZT`) und Ausdrücke mit Programmkonstanten bleiben symbolisch.
        if text.contains("|") || text.contains("[") {
            return .symbol(text.split(separator: " ").joined())
        }
        var tokens: [String] = []
        var token = ""
        for ch in text {
            if ch == "+" || ch == "-" {
                if !token.trimmingCharacters(in: .whitespaces).isEmpty { tokens.append(token.trimmingCharacters(in: .whitespaces)) }
                tokens.append(String(ch))
                token = ""
            } else {
                token.append(ch)
            }
        }
        if !token.trimmingCharacters(in: .whitespaces).isEmpty { tokens.append(token.trimmingCharacters(in: .whitespaces)) }

        let signed = tokens.first == "+" || tokens.first == "-"
        var result: CODValue? = signed ? .int(base ?? 0) : nil
        var op = "+"
        for t in tokens {
            if t == "+" || t == "-" {
                op = t
                continue
            }
            guard let operand = atom(t) else { return nil }
            if let r = result {
                // Rechnen mit unbekannten Konstanten (`GFXCHAT+0`) ergibt einen symbolischen Wert.
                result = combine(r, operand, op) ?? .symbol(text.split(separator: " ").joined())
            } else {
                result = operand
            }
        }
        return result
    }

    private func combine(_ a: CODValue, _ b: CODValue, _ op: String) -> CODValue? {
        switch (a, b) {
        case (.int(let x), .int(let y)): return .int(op == "+" ? x + y : x - y)
        default:
            guard let x = a.doubleValue, let y = b.doubleValue else { return nil }
            return .float(op == "+" ? x + y : x - y)
        }
    }

    private func atom(_ token: String) -> CODValue? {
        if let v = Int(token) { return .int(v) }
        if let v = Double(token) { return .float(v) }
        guard isIdentifier(token) else { return nil }
        if let v = variables[token] { return v }
        if let v = current?.fields[token]?.first { return v }
        return .symbol(token)
    }

    private func isIdentifier(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, first == "_" || first.properties.isAlphabetic else { return false }
        return s.unicodeScalars.allSatisfy { $0 == "_" || $0.properties.isAlphabetic || ("0"..."9").contains($0) }
    }

    private mutating func fail(_ line: Int, _ text: String) {
        unparsed.append((line, text))
    }

    mutating func finish() -> CODDocument {
        commitItem()
        return CODDocument(variables: variables, collections: collections, singletons: singletons, unparsedLines: unparsed)
    }
}
