import AnnoFormats
import AnnoRender
import simd
import Metal

/// Inhalt einer Kartenansicht: eine einzelne Insel oder eine ganze Welt.
@MainActor
protocol MapContent: AnyObject {
    var grid: any TileGrid { get }
    var title: String { get }
    /// Kartenposition, auf die die Kamera beim Laden zeigt (`nil` = Mitte).
    var focus: SIMD2<Float>? { get }
    func update(dt: Double)
    func figures(layout: IsometricLayout, library: SpriteLibrary, timeMs: Int) -> [FigureSprite]
}

/// Kartenansicht: Kamera, Zoomstufe, Blickrichtung und Zeichnen eines `MapContent`.
@MainActor
final class MapScene {
    private let gameData: GameData
    private let device: MTLDevice
    private var libraries: [ZoomLevel: SpriteLibrary] = [:]

    private(set) var content: MapContent?
    private(set) var zoom: ZoomLevel = .medium
    private(set) var rotation = 0
    /// Bildmitte als Kartenposition (in Feldern), unabhängig von Zoom und Drehung.
    private(set) var focus = SIMD2<Float>(0, 0)
    /// Zuletzt sichtbarer Anteil an Meer (für Umgebungsgeräusche).
    private(set) var seaFraction: Float = 0

    /// Atlas-Archive je Zoomstufe: Gelände, Schiffe, Tiere.
    static let archives = ["STADTFLD", "SHIP", "TIERE"]

    init(gameData: GameData, device: MTLDevice) {
        self.gameData = gameData
        self.device = device
    }

    func show(_ content: MapContent) {
        self.content = content
        let grid = content.grid
        focus = content.focus ?? SIMD2(Float(grid.width) / 2, Float(grid.height) / 2)
    }

    private func layout() -> IsometricLayout? {
        guard let grid = content?.grid else { return nil }
        return IsometricLayout(mapWidth: grid.width, mapHeight: grid.height, rotation: rotation, zoom: zoom)
    }

    func rotate(_ delta: Int) { rotation = ((rotation + delta) % 4 + 4) % 4 }

    func setFocus(_ p: SIMD2<Float>) { focus = p }

    func setZoom(_ level: ZoomLevel) { zoom = level }

    /// Verschiebt die Kamera um `delta` Punkte auf dem Bildschirm.
    func pan(by delta: SIMD2<Float>) {
        guard let layout = layout() else { return }
        let center = layout.pixel(ofScreen: layout.screenPosition(ofMap: focus))
        focus = layout.mapPosition(ofScreen: layout.screen(ofPixel: center + delta))
        if let grid = content?.grid {
            focus = simd_clamp(focus, .zero, SIMD2(Float(grid.width), Float(grid.height)))
        }
    }

    func library() throws -> SpriteLibrary {
        if let library = libraries[zoom] { return library }
        let library = try SpriteLibrary(device: device, gameData: gameData, zoom: zoom, names: Self.archives)
        libraries[zoom] = library
        return library
    }

    /// Ecken des sichtbaren Ausschnitts in Kartenkoordinaten.
    func viewCorners(viewSize: SIMD2<Float>) -> [SIMD2<Float>] {
        guard let layout = layout() else { return [] }
        let center = layout.pixel(ofScreen: layout.screenPosition(ofMap: focus))
        return [SIMD2<Float>(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)].map { corner in
            layout.mapPosition(ofScreen: layout.screen(ofPixel: center + corner * viewSize / 2))
        }
    }

    /// Kartenfeld unter einem Punkt der Ansicht (Punkte, Ursprung oben links).
    func pick(viewPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> (x: Int, y: Int)? {
        guard let content, let layout = layout() else { return nil }
        let center = layout.pixel(ofScreen: layout.screenPosition(ofMap: focus)).rounded(.down)
        return layout.pick(pixel: center + viewPoint - viewSize / 2, grid: content.grid)
    }

    func draw(
        renderer: SpriteRenderer, encoder: MTLRenderCommandEncoder, drawableSize: SIMD2<Float>, backingScale: Float, timeMs: Int,
        overlay: (IsometricLayout, SpriteLibrary) -> [SpriteDraw] = { _, _ in [] }
    ) {
        guard let content, let layout = layout(), let library = try? library() else { return }
        let scale = backingScale
        let center = layout.pixel(ofScreen: layout.screenPosition(ofMap: focus)).rounded(.down)
        let halfView = drawableSize / (2 * scale)
        let visible = (min: center - halfView, max: center + halfView)

        let figures = content.figures(layout: layout, library: library, timeMs: timeMs)
        let offset = library.offsets["STADTFLD"] ?? 0
        let draws = layout.sprites(
            for: content.grid, visible: visible, timeMs: timeMs, figures: figures, tileOffset: offset,
            spriteSize: library.size(of:)) + overlay(layout, library)
        renderer.draw(
            draws, from: library.sheet,
            transform: ViewTransform(drawableSize: drawableSize, scale: scale, offset: (drawableSize / 2 - center * scale).rounded(.down)),
            encoder: encoder)
        seaFraction = sampleSea(layout: layout, visible: visible)
    }

    /// Stichprobe: wie viel des sichtbaren Ausschnitts ist Wasser?
    private func sampleSea(layout: IsometricLayout, visible: (min: SIMD2<Float>, max: SIMD2<Float>)) -> Float {
        guard let grid = content?.grid else { return 0 }
        var sea = 0
        var total = 0
        for i in 0..<8 {
            for j in 0..<8 {
                let p = visible.min + (visible.max - visible.min) * SIMD2(Float(i) + 0.5, Float(j) + 0.5) / 8
                let m = layout.mapPosition(ofScreen: layout.screen(ofPixel: p))
                guard let tile = grid.tile(x: Int(m.x.rounded(.down)), y: Int(m.y.rounded(.down))) else { continue }
                total += 1
                if tile.building.elevation == 0 { sea += 1 }
            }
        }
        return total == 0 ? 0 : Float(sea) / Float(total)
    }

    var title: String {
        guard let content else { return "" }
        return "\(content.title)  ·  Zoom \(zoom.directory)  ·  Blick \(rotation * 90)°"
    }
}

/// Richtung 0…7 (0 = rechts oben, im Uhrzeigersinn) für eine Bewegung auf der Karte, wie sie auf dem Bildschirm erscheint.
func screenDirection(of mapDelta: SIMD2<Float>, layout: IsometricLayout) -> Int {
    let a = layout.screenPosition(ofMap: .zero)
    let b = layout.screenPosition(ofMap: mapDelta)
    let s = b - a
    let px = s.x - s.y
    let py = (s.x + s.y) / 2
    let k = Int((atan2(-py, px) / (.pi / 4)).rounded())
    return ((1 - k) % 8 + 8) % 8
}
