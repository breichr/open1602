import AnnoFormats
import AnnoRender
import AnnoSim
import AppKit
import Metal
import simd

/// Bauleiste rechts (nach `GADDATA/BAU.GAD`), Statuszeile und Bauwerkzeuge auf der Karte.
@MainActor
final class BuildInterface {
    enum Tool: Equatable {
        case none
        case build
        case demolish
    }

    private let library: SpriteLibrary
    private let minimap: Minimap
    private let catalogue: [BuildCategory: [BuildingType]]
    private(set) var tool: Tool = .none
    private var category: BuildCategory = .harbour
    private var choice: [BuildCategory: Int] = [:]
    private(set) var rotation = 0
    /// Feld unter der Maus (Weltkoordinaten).
    private(set) var hover: (x: Int, y: Int)?
    /// Startfeld beim Ziehen von Straßen.
    private var dragStart: (x: Int, y: Int)?
    private(set) var message: String?

    /// Breite der Leiste in Punkten (Originalauflösung 1024×768).
    static let panelWidth: Float = 256
    static let player = 0
    static let font = "ZEI"

    // Bildnummern in TOOLS.BSH (aus BAU.GAD).
    static let gfxPanel = 0, gfxCategory = 22, gfxCategorySelected = 31, gfxPrev = 40, gfxNext = 41
    static let gfxTitle = 172, gfxCoin = 46, gfxBricks = 47, gfxTools = 48, gfxWood = 49, gfxUpkeep = 52
    static let categoryRects: [SIMD4<Float>] = [
        SIMD4(17, 623, 56, 64), SIMD4(72, 623, 56, 64), SIMD4(129, 623, 56, 64), SIMD4(185, 623, 56, 64),
        SIMD4(17, 692, 56, 64), SIMD4(72, 692, 56, 64), SIMD4(129, 692, 58, 64), SIMD4(188, 692, 59, 64),
    ]
    static let prevRect = SIMD4<Float>(11, 413, 40, 46)
    static let nextRect = SIMD4<Float>(210, 413, 40, 60)
    static let iconRect = SIMD4<Float>(48, 390, 160, 110)
    /// Aussparungen in TOOLS #0: Minikarte und vier Felder darunter (aus der Grafik vermessen).
    static let minimapRect = SIMD4<Float>(33, 16, 182, 154)
    static let slotRects: [SIMD4<Float>] = [
        SIMD4(27, 286, 45, 42), SIMD4(81, 286, 45, 42), SIMD4(135, 286, 45, 42), SIMD4(189, 286, 45, 42),
    ]

    init(device: MTLDevice, gameData: GameData, buildings: BuildingTable) throws {
        minimap = Minimap(device: device, palette: try Palette(colFile: gameData.read("ToolGfx/STADTFLD.COL")))
        library = try SpriteLibrary(device: device, gameData: gameData, files: [
            ("TOOLS", "ToolGfx/TOOLS.BSH"), ("BAUHAUS", "ToolGfx/BAUHAUS.BSH"), ("ZEI", "ToolGfx/ZEI16V.ZEI"),
        ])
        // Je Kategorie die baubaren Gebäude, eine Variante je Symbol.
        var catalogue: [BuildCategory: [BuildingType]] = [:]
        for type in buildings.types.values.sorted(by: { $0.id < $1.id }) {
            guard let category = type.buildCategory else { continue }
            if catalogue[category]?.contains(where: { $0.buildIcon == type.buildIcon }) == true { continue }
            catalogue[category, default: []].append(type)
        }
        self.catalogue = catalogue
    }

    var selected: BuildingType? {
        guard tool == .build, let list = catalogue[category], !list.isEmpty else { return nil }
        return list[(choice[category] ?? 0) % list.count]
    }

    private var shownBuilding: BuildingType? {
        guard let list = catalogue[category], !list.isEmpty else { return nil }
        return list[(choice[category] ?? 0) % list.count]
    }

    // MARK: Eingabe

    /// Weltposition unter einem Punkt der Minikarte (Leistenkoordinaten), sonst `nil`.
    func minimapTarget(at p: SIMD2<Float>, world: WorldMap) -> SIMD2<Float>? {
        let r = Self.minimapRect
        guard p.x >= r.x, p.y >= r.y, p.x < r.x + r.z, p.y < r.y + r.w else { return nil }
        let (scale, origin) = Self.minimapFit(world: world)
        return (p - origin) / scale
    }

    /// Maßstab und Lage der Welt in der Minikarte (seitenverhältnistreu, zentriert).
    static func minimapFit(world: WorldMap) -> (scale: Float, origin: SIMD2<Float>) {
        let r = minimapRect
        let scale = min(r.z / Float(world.width), r.w / Float(world.height))
        let size = SIMD2(Float(world.width), Float(world.height)) * scale
        return (scale, SIMD2(r.x, r.y) + (SIMD2(r.z, r.w) - size) / 2)
    }

    /// Klick in die Leiste (Punkte relativ zur linken oberen Ecke der Leiste). `true`, wenn behandelt.
    func clickPanel(at p: SIMD2<Float>) -> Bool {
        func hit(_ r: SIMD4<Float>) -> Bool { p.x >= r.x && p.y >= r.y && p.x < r.x + r.z && p.y < r.y + r.w }
        if let index = Self.categoryRects.firstIndex(where: hit), let category = BuildCategory(rawValue: index) {
            if self.category == category && tool == .build {
                tool = .none
            } else {
                self.category = category
                tool = .build
            }
            return true
        }
        if hit(Self.prevRect) { cycle(-1); return true }
        if hit(Self.nextRect) { cycle(1); return true }
        if hit(Self.iconRect) { tool = .build; return true }
        return p.x >= 0 && p.x < Self.panelWidth
    }

    func cycle(_ delta: Int) {
        let count = catalogue[category]?.count ?? 1
        choice[category] = (((choice[category] ?? 0) + delta) % count + count) % count
        tool = .build
    }

    func rotate(_ delta: Int) { rotation = ((rotation + delta) % 4 + 4) % 4 }

    func toggleDemolish() { tool = tool == .demolish ? .none : .demolish }

    func cancel() {
        tool = .none
        dragStart = nil
        message = nil
    }

    func setHover(_ cell: (x: Int, y: Int)?) { hover = cell }

    func mouseDown(at cell: (x: Int, y: Int)?) {
        guard let cell else { return }
        if selected?.kind == "STRASSE" { dragStart = cell }
    }

    /// Maustaste losgelassen über `cell`: bauen oder abreißen.
    func mouseUp(at cell: (x: Int, y: Int)?, session: WorldSession) {
        defer { dragStart = nil }
        guard let cell else { return }
        switch tool {
        case .none:
            return
        case .demolish:
            let ok = session.mutateGame { $0.demolish(x: cell.x, y: cell.y, player: Self.player) }
            message = ok ? nil : "Hier kann nichts abgerissen werden"
        case .build:
            guard let type = selected else { return }
            if type.kind == "STRASSE" {
                let path = Self.roadPath(from: dragStart ?? cell, to: cell)
                let built = session.mutateGame { $0.buildRoad(type, path: path, player: Self.player) }
                message = built == 0 ? problems(type, at: cell, session: session).first?.description : nil
            } else {
                let problems = session.mutateGame { $0.build(type, x: cell.x, y: cell.y, rotation: rotation, player: Self.player) }
                message = problems.first?.description
            }
        }
    }

    /// L-förmiger Weg: erst entlang x, dann entlang y.
    static func roadPath(from a: (x: Int, y: Int), to b: (x: Int, y: Int)) -> [(x: Int, y: Int)] {
        var path: [(x: Int, y: Int)] = []
        let sx = b.x >= a.x ? 1 : -1
        let sy = b.y >= a.y ? 1 : -1
        for x in stride(from: a.x, through: b.x, by: sx) { path.append((x, a.y)) }
        for y in stride(from: a.y + sy, through: b.y, by: sy) where a.y != b.y { path.append((b.x, y)) }
        return path
    }

    private func problems(_ type: BuildingType, at cell: (x: Int, y: Int), session: WorldSession) -> [PlacementProblem] {
        session.game.check(type, x: cell.x, y: cell.y, rotation: rotation, player: Self.player)
    }

    // MARK: Vorschau auf der Karte

    /// Bauvorschau (grün = möglich, rot = nicht möglich) oder Abrissmarkierung.
    func previewSprites(session: WorldSession, layout: IsometricLayout, mapLibrary: SpriteLibrary, timeMs: Int) -> [SpriteDraw] {
        guard let hover else { return [] }
        let offset = mapLibrary.offsets["STADTFLD"] ?? 0
        let game = session.game
        switch tool {
        case .none:
            return []
        case .demolish:
            guard let tile = game.world.tile(x: hover.x, y: hover.y) else { return [] }
            let island = game.world.islandIndex(atX: hover.x, y: hover.y)
            let local = island.map { (hover.x - game.world.islands[$0].x, hover.y - game.world.islands[$0].y) }
            guard let island, let local, let fp = game.world.islands[island].map.footprint(atX: local.0, y: local.1) else { return [] }
            var draws: [SpriteDraw] = []
            let origin = game.world.islands[island]
            for dy in 0..<fp.height {
                for dx in 0..<fp.width {
                    let x = origin.x + fp.x + dx
                    let y = origin.y + fp.y + dy
                    guard let t = game.world.tile(x: x, y: y) else { continue }
                    if let d = layout.tileSprite(t, mapX: x, mapY: y, timeMs: timeMs, tileOffset: offset, tint: SpriteDraw.invalidTint, spriteSize: mapLibrary.size(of:)) {
                        draws.append(d)
                    }
                }
            }
            _ = tile
            return draws
        case .build:
            guard let type = selected else { return [] }
            // Straßen: Form jedes Feldes wie nach dem Bau (Kurven, T-Stücke, Anschluss an vorhandene Wege).
            let cells: [(x: Int, y: Int, building: BuildingType, rotation: Int)] =
                type.kind == "STRASSE"
                ? game.roadPreview(type, path: Self.roadPath(from: dragStart ?? hover, to: hover))
                : [(hover.x, hover.y, type, type.rotateStride > 0 ? rotation : 0)]
            var draws: [SpriteDraw] = []
            for cell in cells {
                // Vorhandene Wege auf dem Pfad bleiben einfach stehen und sind deshalb kein Fehler.
                let existingRoad = type.kind == "STRASSE" && game.world.tile(x: cell.x, y: cell.y)?.building.kind == "STRASSE"
                let ok = existingRoad || game.check(type, x: cell.x, y: cell.y, rotation: rotation, player: Self.player).isEmpty
                let type = cell.building
                let rotation = cell.rotation
                let (w, h) = type.footprint(rotation: rotation)
                // Teile in Zeichenreihenfolge (hinten nach vorne).
                var parts: [(Int, Int)] = []
                for dy in 0..<h {
                    for dx in 0..<w { parts.append((dx, dy)) }
                }
                parts.sort { layout.screenCell(x: $0.0, y: $0.1).x + layout.screenCell(x: $0.0, y: $0.1).y < layout.screenCell(x: $1.0, y: $1.1).x + layout.screenCell(x: $1.0, y: $1.1).y }
                for (dx, dy) in parts {
                    let tile = IslandTile(building: type, fieldIndex: -1, rotation: rotation, animation: 0, random: 0, dx: dx, dy: dy)
                    if let d = layout.tileSprite(
                        tile, mapX: cell.x + dx, mapY: cell.y + dy, timeMs: timeMs, tileOffset: offset,
                        tint: ok ? Self.silhouetteTint : SpriteDraw.invalidTint, spriteSize: mapLibrary.size(of:))
                    {
                        draws.append(d)
                    }
                }
            }
            return draws
        }
    }

    // MARK: Einflussbereich

    /// Im Baumodus wird wie im Original alles außerhalb des eigenen Einflussbereichs abgedunkelt.
    func tileTint(session: WorldSession) -> ((Int, Int) -> SIMD4<UInt8>?)? {
        guard tool == .build, selected != nil else { return nil }
        let game = session.game
        return { x, y in
            game.isInfluenced(x: x, y: y, by: Self.player) ? nil : Self.outsideTint
        }
    }

    static let outsideTint = SIMD4<UInt8>(0, 0, 0, 105)
    /// Bauvorschau als sandfarbene Silhouette (wie im Original).
    static let silhouetteTint = SIMD4<UInt8>(232, 196, 120, 205)
    static let radiusColor = SIMD4<UInt8>(255, 215, 70, 255)

    /// Gepunktete Linie um den Einflussbereich, den das geplante Gebäude hätte (Kontor, Marktplatz).
    func radiusOutline(session: WorldSession, layout: IsometricLayout) -> [SpriteDraw] {
        guard tool == .build, let type = selected, let hover,
            let p = session.game.influencePreview(type, x: hover.x, y: hover.y, rotation: rotation)
        else { return [] }
        let world = session.game.world
        func inside(_ x: Int, _ y: Int) -> Bool {
            let dx = Float(x) + 0.5 - p.x
            let dy = Float(y) + 0.5 - p.y
            return dx * dx + dy * dy <= p.radius * p.radius
        }
        let dot = max(Float(2 >> layout.zoom.rawValue), 1)
        var draws: [SpriteDraw] = []
        let r = Int(p.radius.rounded(.up)) + 1
        for y in Int(p.y) - r...Int(p.y) + r {
            for x in Int(p.x) - r...Int(p.x) + r where inside(x, y) {
                let lift = Float(layout.zoom.scaledElevation(world.tile(x: x, y: y)?.building.elevation ?? 0))
                let edges: [(Bool, SIMD2<Float>, SIMD2<Float>)] = [
                    (!inside(x, y - 1), SIMD2(Float(x), Float(y)), SIMD2(Float(x + 1), Float(y))),
                    (!inside(x + 1, y), SIMD2(Float(x + 1), Float(y)), SIMD2(Float(x + 1), Float(y + 1))),
                    (!inside(x, y + 1), SIMD2(Float(x), Float(y + 1)), SIMD2(Float(x + 1), Float(y + 1))),
                    (!inside(x - 1, y), SIMD2(Float(x), Float(y)), SIMD2(Float(x), Float(y + 1))),
                ]
                for (isBorder, a, b) in edges where isBorder {
                    for t: Float in [0.17, 0.5, 0.83] {
                        let m = a + (b - a) * t
                        let pixel = layout.pixel(ofScreen: layout.screenPosition(ofMap: m)) - SIMD2(dot / 2, dot / 2 + lift)
                        draws.append(SpriteDraw(index: Minimap.whiteIndex, position: pixel, tint: Self.radiusColor, size: SIMD2(dot, dot)))
                    }
                }
            }
        }
        return draws
    }

    /// Zeichnet die Radiuslinie im Koordinatensystem der Karte.
    func drawMapOverlay(renderer: SpriteRenderer, encoder: MTLRenderCommandEncoder, transform: ViewTransform, layout: IsometricLayout, session: WorldSession) {
        minimap.update(world: session.game.world, revision: session.revision)
        guard let sheet = minimap.sheet else { return }
        let dots = radiusOutline(session: session, layout: layout)
        if !dots.isEmpty { renderer.draw(dots, from: sheet, transform: transform, encoder: encoder) }
    }

    // MARK: Leiste und Statuszeile

    /// Zeichnet Leiste (rechts), Minikarte und Statuszeile (oben links) in Punkten.
    /// - Parameter viewCorners: Ecken des sichtbaren Kartenausschnitts in Weltkoordinaten (für den Rahmen).
    func draw(
        renderer: SpriteRenderer, encoder: MTLRenderCommandEncoder, drawableSize: SIMD2<Float>, backingScale: Float,
        session: WorldSession, viewCorners: [SIMD2<Float>]
    ) {
        let viewWidth = drawableSize.x / backingScale
        let transform = ViewTransform(drawableSize: drawableSize, scale: backingScale)

        // Minikarte und dunkle Felder hinter der Leiste.
        minimap.update(world: session.game.world, revision: session.revision)
        if let sheet = minimap.sheet {
            let panelX = viewWidth - Self.panelWidth
            let (scale, origin) = Self.minimapFit(world: session.game.world)
            let r = Self.minimapRect
            var mini = [SpriteDraw(index: Minimap.blackIndex, position: SIMD2(panelX + r.x, r.y), size: SIMD2(r.z, r.w))]
            mini += Self.slotRects.map { SpriteDraw(index: Minimap.blackIndex, position: SIMD2(panelX + $0.x, $0.y), size: SIMD2($0.z, $0.w)) }
            let world = session.game.world
            mini.append(SpriteDraw(
                index: Minimap.imageIndex, position: SIMD2(panelX, 0) + origin,
                size: SIMD2(Float(world.width), Float(world.height)) * scale))
            // Sichtbarer Ausschnitt als Rahmen.
            let points = viewCorners.map { SIMD2(panelX, 0) + origin + $0 * scale }
            if points.count == 4 {
                let lo = simd_clamp(simd_min(simd_min(points[0], points[1]), simd_min(points[2], points[3])), SIMD2(panelX + r.x, r.y), SIMD2(panelX + r.x + r.z, r.y + r.w))
                let hi = simd_clamp(simd_max(simd_max(points[0], points[1]), simd_max(points[2], points[3])), SIMD2(panelX + r.x, r.y), SIMD2(panelX + r.x + r.z, r.y + r.w))
                for (p, s) in [(lo, SIMD2(hi.x - lo.x, 1)), (SIMD2(lo.x, hi.y - 1), SIMD2(hi.x - lo.x, 1)), (lo, SIMD2(1, hi.y - lo.y)), (SIMD2(hi.x - 1, lo.y), SIMD2(1, hi.y - lo.y))] {
                    mini.append(SpriteDraw(index: Minimap.whiteIndex, position: p, size: s))
                }
            }
            renderer.draw(mini, from: sheet, transform: transform, encoder: encoder)
        }
        var draws: [SpriteDraw] = []
        let panelX = viewWidth - Self.panelWidth
        func add(_ gfx: Int, _ x: Float, _ y: Float, archive: String = "TOOLS") {
            draws.append(SpriteDraw(index: library.index(archive, gfx), position: SIMD2(panelX + x, y)))
        }
        func text(_ s: String, _ x: Float, _ y: Float) {
            draws += library.text(s, font: Self.font, at: SIMD2(x, y)).draws
        }
        func centeredText(_ s: String, centerX: Float, y: Float) {
            let width = library.text(s, font: Self.font, at: .zero).width
            text(s, centerX - width / 2, y)
        }

        add(Self.gfxPanel, 0, 0)
        for (i, r) in Self.categoryRects.enumerated() {
            let selected = tool == .build && category.rawValue == i
            add(selected ? Self.gfxCategorySelected + i : Self.gfxCategory + i, r.x, r.y)
        }
        if let building = shownBuilding {
            add(Self.gfxTitle, 6, 354)
            centeredText(Self.name(of: building), centerX: panelX + 128, y: 360)
            add(Self.gfxPrev, Self.prevRect.x, Self.prevRect.y)
            add(Self.gfxNext, Self.nextRect.x, Self.nextRect.y)
            if let icon = building.buildIcon, let size = library.size(of: library.index("BAUHAUS", icon)) {
                add(icon, 48 + (160 - Float(size.width)) / 2, 390 + (110 - Float(size.height)) / 2, archive: "BAUHAUS")
            }
            if let cost = building.buildCost {
                add(Self.gfxCoin, 16, 564)
                text("\(cost.money)", panelX + 50, 570)
                if let upkeep = building.upkeep {
                    add(Self.gfxUpkeep, 128, 564)
                    text("\(upkeep)", panelX + 162, 570)
                }
                add(Self.gfxTools, 16, 594)
                text("\(cost.tools)", panelX + 50, 600)
                add(Self.gfxWood, 72, 594)
                text("\(cost.wood)", panelX + 106, 600)
                add(Self.gfxBricks, 128, 594)
                text("\(cost.bricks)", panelX + 162, 600)
            }
            if building.rotateStride > 0 { text("Drehung \(rotation * 90)°  ( , . )", panelX + 60, 470) }
        }

        // Statuszeile: Geld und Lager der Insel unter der Maus (bzw. Schiffsladung).
        let game = session.game
        let player = game.players.indices.contains(Self.player) ? game.players[Self.player] : nil
        let island = hover.flatMap { game.world.islandIndex(atX: $0.x, y: $0.y) }
        let stock = island.flatMap { game.settlement(player: Self.player, island: $0)?.stock } ?? player?.shipCargo ?? Stock()
        var x: Float = 10
        // Wie im Original: hinter jedem Vorrat in Klammern die Kosten des gewählten Gebäudes.
        let cost = selected?.buildCost
        let entries: [(Int, Int, Int?)] = [
            (Self.gfxCoin, player?.money ?? 0, cost?.money), (Self.gfxTools, stock[.tools], cost?.tools),
            (Self.gfxWood, stock[.wood], cost?.wood), (Self.gfxBricks, stock[.bricks], cost?.bricks),
        ]
        for (gfx, value, price) in entries {
            draws.append(SpriteDraw(index: library.index("TOOLS", gfx), position: SIMD2(x, 6)))
            x += 34
            let label = library.text(price.map { "\(value) (\($0))" } ?? "\(value)", font: Self.font, at: SIMD2(x, 12))
            draws += label.draws
            x += max(label.width, 24) + 18
        }
        if let message {
            draws += library.text(message, font: Self.font, at: SIMD2(10, 44), tint: SIMD4(255, 80, 80, 200)).draws
        } else if tool == .demolish {
            draws += library.text("Abreißen: Gebäude anklicken (D beendet)", font: Self.font, at: SIMD2(10, 44)).draws
        }

        renderer.draw(draws, from: library.sheet, transform: transform, encoder: encoder)
    }

    /// Anzeigename. Die Originalnamen stehen in `Language.dll`; bis dahin ein lesbarer Name aus den Daten.
    static func name(of type: BuildingType) -> String {
        let names: [String: String] = [
            "KONTOR": "Kontor", "WOHNUNG": "Wohnhaus", "HANDWERK": "Handwerksbetrieb", "PLANTAGE": "Farm/Plantage",
            "FISCHEREI": "Fischerei", "KIRCHE": "Kirche", "KAPELLE": "Kapelle", "WIRT": "Wirtshaus", "WACHTURM": "Wachturm",
            "STEINBRUCH": "Steinbruch", "BERGWERK": "Bergwerk", "JAGDHAUS": "Jagdhütte", "WERFT": "Werft",
            "ROHSTWACHS": "Bäume pflanzen", "pMAUER": "Mauer", "MARKT": "Marktplatz", "BRUNNEN": "Brunnen",
            "SCHULE": "Schule", "ARZT": "Arzt", "BADE": "Badehaus", "THEATER": "Theater", "HOCHSCHULE": "Hochschule",
            "GALGEN": "Galgen", "SCHLOSS": "Schloss", "KATHETRALE": "Kathedrale", "DENKMAL": "Denkmal", "TRIUMPH": "Triumphbogen",
            "MILITAR": "Burg", "KANONTURM": "Kanonenturm",
        ]
        if type.kind == "STRASSE" { return type.id < 410 ? "Steinstraße" : "Feldweg" }
        if type.kind == "BRUECKE" { return "Brücke" }
        if type.kind == "PIER" { return "Steg" }
        return names[type.production ?? ""] ?? type.kind.capitalized
    }
}
