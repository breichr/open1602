import AnnoFormats
import AnnoRender
import Metal

/// Inselansicht: lädt Inselvorlagen, hält Kamera, Zoomstufe und Blickrichtung.
@MainActor
final class IslandScene {
    private let gameData: GameData
    private let device: MTLDevice
    private let buildings: BuildingTable

    let islandFiles: [String]
    private(set) var fileIndex = 0
    private(set) var zoom: ZoomLevel = .large
    private(set) var rotation = 0
    /// Bildmitte in virtuellen Pixeln der aktuellen Zoomstufe.
    private(set) var camera = SIMD2<Float>(0, 0)

    private var sheets: [ZoomLevel: SpriteSheet] = [:]
    private(set) var map: IslandMap?
    private(set) var header: IslandHeader?
    private var cachedDraws: [SpriteDraw]?

    init(gameData: GameData, device: MTLDevice) throws {
        self.gameData = gameData
        self.device = device
        buildings = try BuildingTable(gameData: gameData)
        islandFiles = (gameData.files(withExtension: "scp")).filter {
            let dir = $0.split(separator: "/").first?.lowercased()
            return dir == "nord" || dir == "sued"
        }
        try loadIsland()
    }

    var currentFile: String { islandFiles[fileIndex] }

    func select(file: String) throws {
        guard let index = islandFiles.firstIndex(where: { $0.lowercased() == file.lowercased() }) else { return }
        fileIndex = index
        try loadIsland()
    }

    func nextIsland(_ delta: Int) throws {
        fileIndex = ((fileIndex + delta) % islandFiles.count + islandFiles.count) % islandFiles.count
        try loadIsland()
    }

    private func loadIsland() throws {
        let island = try IslandFile(bytes: gameData.read(currentFile))
        let base = try IslandFile.baseTemplatePath(for: currentFile).flatMap { path in
            gameData.url(for: path) != nil ? try IslandFile(bytes: gameData.read(path)) : nil
        }
        header = island.header
        map = IslandMap(island: island, base: base, buildings: buildings)
        cachedDraws = nil
        centerCamera()
    }

    func rotate(_ delta: Int) {
        let center = mapPoint(at: camera)
        rotation = ((rotation + delta) % 4 + 4) % 4
        cachedDraws = nil
        camera = screenPoint(ofMap: center)
    }

    func setZoom(_ level: ZoomLevel) {
        guard level != zoom else { return }
        let factor = Float(level.tileWidth) / Float(zoom.tileWidth)
        camera *= factor
        zoom = level
        cachedDraws = nil
    }

    func pan(by delta: SIMD2<Float>) {
        camera += delta
    }

    private func layout() -> IsometricLayout? {
        guard let map else { return nil }
        return IsometricLayout(mapWidth: map.width, mapHeight: map.height, rotation: rotation, zoom: zoom)
    }

    private func centerCamera() {
        guard let layout = layout() else { return }
        let bounds = layout.groundBounds
        camera = (bounds.min + bounds.max) / 2
    }

    /// Kartenposition (in Feldern, kontinuierlich) unter einem Punkt in virtuellen Pixeln.
    private func mapPoint(at point: SIMD2<Float>) -> SIMD2<Float> {
        guard let layout = layout() else { return .zero }
        let hw = Float(zoom.tileWidth) / 2
        let rs = Float(zoom.rowStep)
        let a = point.x / hw  // sx - sy
        let b = point.y / rs  // sx + sy
        let sx = (a + b) / 2
        let sy = (b - a) / 2
        let (gw, gh) = layout.screenGrid
        // Kontinuierliche Variante von `mapCell`.
        switch rotation {
        case 0: return SIMD2(sx, sy)
        case 1: return SIMD2(sy, Float(gw) - sx)
        case 2: return SIMD2(Float(gw) - sx, Float(gh) - sy)
        default: return SIMD2(Float(gh) - sy, sx)
        }
    }

    private func screenPoint(ofMap p: SIMD2<Float>) -> SIMD2<Float> {
        guard let layout = layout(), let map else { return .zero }
        let (sx, sy): (Float, Float) =
            switch rotation {
            case 0: (p.x, p.y)
            case 1: (Float(map.height) - p.y, p.x)
            case 2: (Float(map.width) - p.x, Float(map.height) - p.y)
            default: (p.y, Float(map.width) - p.x)
            }
        _ = layout
        return SIMD2((sx - sy) * Float(zoom.tileWidth) / 2, (sx + sy) * Float(zoom.rowStep))
    }

    private func sheet() throws -> SpriteSheet {
        if let sheet = sheets[zoom] { return sheet }
        let archive = try BSHArchive(fileBytes: gameData.read("\(zoom.directory)/STADTFLD.BSH"))
        let sheet = try SpriteSheet(device: device, archive: archive)
        sheets[zoom] = sheet
        return sheet
    }

    func draw(renderer: SpriteRenderer, encoder: MTLRenderCommandEncoder, drawableSize: SIMD2<Float>, backingScale: Float) {
        guard let map, let layout = layout(), let sheet = try? sheet() else { return }
        if cachedDraws == nil {
            cachedDraws = layout.sprites(for: map) { index in
                guard sheet.placements.indices.contains(index) else { return nil }
                let p = sheet.placements[index]
                return (p.width, p.height)
            }
        }
        let scale = backingScale
        let offset = (drawableSize / 2 - camera * scale).rounded(.down)
        renderer.draw(
            cachedDraws ?? [], from: sheet,
            transform: ViewTransform(drawableSize: drawableSize, scale: scale, offset: offset), encoder: encoder)
    }

    var title: String {
        guard let header, let map else { return currentFile }
        var parts = ["\(currentFile)  \(header.width)×\(header.height)", "Zoom \(zoom.directory)", "Blick \(rotation * 90)°"]
        if !map.unknownBuildingIDs.isEmpty { parts.append("\(map.unknownBuildingIDs.count) unbekannte IDs") }
        if !map.isComplete { parts.append("unvollständig") }
        return parts.joined(separator: "  ·  ")
    }
}
