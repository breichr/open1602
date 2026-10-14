import AnnoFormats
import AnnoRender
import AppKit
import MetalKit
import simd

/// Steuert, was die App anzeigt (Tab wechselt): Startbildschirm, Welt, Inselbrowser, Sprite-Viewer.
@MainActor
final class GameController: NSObject, MTKViewDelegate, NSWindowDelegate {
    enum Mode {
        /// Startbildschirm, 1024×768 seitenverhältnistreu ins Fenster skaliert.
        case title
        /// Szenario-Welt: Inseln, Schiffe, Tiere.
        case world
        /// Einzelne Inselvorlagen.
        case island
        /// Sprite-Browser: ←/→ Bild, ↑/↓ Datei, +/− Zoom.
        case viewer
    }

    private let gameData: GameData
    private let view: GameView
    private let commandQueue: MTLCommandQueue
    private let renderer: SpriteRenderer
    private let audio: AudioController

    private var mode: Mode = .title
    private let titleSheet: SpriteSheet
    private let mapScene: MapScene
    private let world: WorldSession
    private let islands: IslandBrowser
    private let buildUI: BuildInterface
    /// Letzte Mausposition beim Ziehen (zum Verschieben der Karte ohne Werkzeug).
    private var lastDrag: SIMD2<Float>?

    private let bshFiles: [String]
    private var fileIndex: Int
    private var imageIndex = 0
    private var zoom: Float = 2
    private var viewerSheet: SpriteSheet?
    private var viewerArchive: BSHArchive?

    /// Spielzeit in Millisekunden (für Animationen).
    private(set) var timeMs = 0
    private var lastFrame: CFTimeInterval?
    private var lastTitleUpdate: CFTimeInterval = 0

    static let titleSize = SIMD2<Float>(1024, 768)

    init(gameData: GameData, view: GameView) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw SpriteRenderer.Error.noMetalDevice
        }
        self.gameData = gameData
        self.view = view
        commandQueue = queue
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        view.preferredFramesPerSecond = 60

        renderer = try SpriteRenderer(device: device, pixelFormat: view.colorPixelFormat)
        try renderer.setPalette(Palette(colFile: gameData.read("ToolGfx/STADTFLD.COL")))
        titleSheet = try SpriteSheet(device: device, archive: BSHArchive(fileBytes: gameData.read("ToolGfx/START.BSH")))
        let buildings = try BuildingTable(gameData: gameData)
        mapScene = MapScene(gameData: gameData, device: device)
        world = try WorldSession(gameData: gameData, buildings: buildings)
        islands = try IslandBrowser(gameData: gameData, buildings: buildings)
        buildUI = try BuildInterface(device: device, gameData: gameData, buildings: buildings)
        audio = AudioController(gameData: gameData)

        bshFiles = gameData.files(withExtension: "bsh")
        fileIndex = bshFiles.firstIndex { $0.lowercased() == "gfx/stadtfld.bsh" } ?? 0
        super.init()
        view.delegate = self
        view.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        view.onPan = { [weak self] delta in self?.pan(by: delta) }
        view.onMouse = { [weak self] event, point in self?.handleMouse(event, at: point) }
    }

    func startAudio() { audio.start() }

    // MARK: Spielschleife und Darstellung

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(now - (lastFrame ?? now), 0.1)
        lastFrame = now
        advance(dt: dt)

        guard
            let pass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commands = commandQueue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let drawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encodeScene(encoder: encoder, drawableSize: drawableSize, backingScale: Float(view.window?.backingScaleFactor ?? 2))
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()

        if mode == .world || mode == .island {
            audio.updateAmbience(seaFraction: mapScene.seaFraction, landVisible: mapScene.seaFraction < 0.9, dt: dt)
        }
        if now - lastTitleUpdate > 1 {
            lastTitleUpdate = now
            updateTitle()
        }
    }

    /// Spielzeit und Simulation vorrücken.
    func advance(dt: Double) {
        timeMs += Int(dt * 1000)
        mapScene.content?.update(dt: dt)
    }

    private func encodeScene(encoder: MTLRenderCommandEncoder, drawableSize: SIMD2<Float>, backingScale: Float) {
        switch mode {
        case .title:
            let transform = ViewTransform.fit(virtualSize: Self.titleSize, drawableSize: drawableSize)
            renderer.draw([SpriteDraw(index: 0, position: .zero)], from: titleSheet, transform: transform, encoder: encoder)
        case .world:
            mapScene.draw(
                renderer: renderer, encoder: encoder, drawableSize: drawableSize, backingScale: backingScale, timeMs: timeMs,
                overlay: { [buildUI, world, timeMs] layout, library in
                    buildUI.previewSprites(session: world, layout: layout, mapLibrary: library, timeMs: timeMs)
                })
            buildUI.draw(
                renderer: renderer, encoder: encoder, drawableSize: drawableSize, backingScale: backingScale, session: world,
                viewCorners: mapScene.viewCorners(viewSize: drawableSize / backingScale))
        case .island:
            mapScene.draw(renderer: renderer, encoder: encoder, drawableSize: drawableSize, backingScale: backingScale, timeMs: timeMs)
        case .viewer:
            if let sheet = currentViewerSheet() {
                let transform = ViewTransform(drawableSize: drawableSize, scale: backingScale * zoom)
                let virtual = drawableSize / transform.scale
                let place = sheet.placements[imageIndex]
                let size = SIMD2<Float>(Float(place.width), Float(place.height))
                let position = ((virtual - size) / 2).rounded(.down)
                renderer.draw([SpriteDraw(index: imageIndex, position: position)], from: sheet, transform: transform, encoder: encoder)
            }
        }
    }

    /// Rendert die aktuelle Szene offscreen und liefert BGRA-Pixel (für `--snapshot`).
    func snapshot(width: Int, height: Int, backingScale: Float) -> [UInt8]? {
        guard let device = view.device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: view.colorPixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = view.clearColor
        pass.colorAttachments[0].storeAction = .store
        guard
            let commands = commandQueue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return nil }
        encodeScene(encoder: encoder, drawableSize: SIMD2(Float(width), Float(height)), backingScale: backingScale)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    private func currentViewerSheet() -> SpriteSheet? {
        if let viewerSheet { return viewerSheet }
        guard let device = view.device else { return nil }
        do {
            let archive = try BSHArchive(fileBytes: gameData.read(bshFiles[fileIndex]))
            viewerArchive = archive
            viewerSheet = try SpriteSheet(device: device, archive: archive)
        } catch {
            NSLog("Konnte %@ nicht laden: %@", bshFiles[fileIndex], String(describing: error))
        }
        return viewerSheet
    }

    func updateTitle() {
        let music = audio.currentTrack.map { "  ·  ♪ \($0)" } ?? ""
        switch mode {
        case .title:
            view.window?.title = "Open1602  ·  Tab: Welt / Inseln / Sprite-Viewer"
        case .world:
            view.window?.title = "\(mapScene.title)  ·  Bauen: Leiste rechts, D Abreißen, Rechtsklick abbrechen  ·  N/P Szenario  G neue Welt  M Musik\(music)"
        case .island:
            view.window?.title = "\(mapScene.title)  ·  N/P Insel  M Musik\(music)"
        case .viewer:
            let count = currentViewerSheet()?.count ?? 0
            var info = "\(bshFiles[fileIndex])  #\(imageIndex) / \(count)"
            if let header = try? viewerArchive?.header(at: imageIndex) {
                info += "  \(header.width)×\(header.height)"
            }
            view.window?.title = "\(info)  ·  \(Int(zoom))×  ·  ←→ Bild  ↑↓ Datei  +− Zoom  Tab Zurück"
        }
    }

    // MARK: Eingabe

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 48 {  // Tab
            switch mode {
            case .title: showWorld()
            case .world: showIslands()
            case .island: mode = .viewer
            case .viewer: mode = .title
            }
        } else {
            let handled = switch mode {
            case .title: false
            case .world, .island: handleMapKey(event)
            case .viewer: handleViewerKey(event)
            }
            guard handled else { return false }
        }
        updateTitle()
        return true
    }

    private func showWorld() {
        mode = .world
        if mapScene.content !== world { mapScene.show(world) }
    }

    private func showIslands() {
        mode = .island
        if mapScene.content !== islands { mapScene.show(islands) }
    }

    // MARK: Maus

    private func handleMouse(_ event: GameView.MouseEvent, at point: SIMD2<Float>) {
        guard mode == .world else {
            if event == .dragged, let last = lastDrag { pan(by: last - point) }
            lastDrag = event == .up ? nil : point
            return
        }
        let viewSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        let panelX = viewSize.x - BuildInterface.panelWidth
        let cell = point.x < panelX ? mapScene.pick(viewPoint: point, viewSize: viewSize) : nil
        switch event {
        case .moved:
            buildUI.setHover(cell)
        case .down:
            lastDrag = point
            if point.x >= panelX {
                let local = SIMD2(point.x - panelX, point.y)
                if let target = buildUI.minimapTarget(at: local, world: world.world) {
                    mapScene.setFocus(target)
                } else {
                    _ = buildUI.clickPanel(at: local)
                }
            } else {
                buildUI.mouseDown(at: cell)
            }
        case .dragged:
            if buildUI.tool == .none, let last = lastDrag {
                mapScene.pan(by: last - point)
            }
            lastDrag = point
            buildUI.setHover(cell)
        case .up:
            lastDrag = nil
            if point.x < panelX { buildUI.mouseUp(at: cell, session: world) }
        case .rightDown:
            buildUI.cancel()
        }
    }

    private func handleMapKey(_ event: NSEvent) -> Bool {
        let step: Float = event.modifierFlags.contains(.shift) ? 400 : 100
        do {
            switch event.keyCode {
            case 53: buildUI.cancel()  // Esc
            case 123: mapScene.pan(by: SIMD2(-step, 0))  // ←
            case 124: mapScene.pan(by: SIMD2(step, 0))  // →
            case 125: mapScene.pan(by: SIMD2(0, step))  // ↓
            case 126: mapScene.pan(by: SIMD2(0, -step))  // ↑
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "+", "=": mapScene.setZoom(ZoomLevel(rawValue: mapScene.zoom.rawValue - 1) ?? .large)
                case "-": mapScene.setZoom(ZoomLevel(rawValue: mapScene.zoom.rawValue + 1) ?? .small)
                case "r": mapScene.rotate(event.modifierFlags.contains(.shift) ? -1 : 1)
                case "m": audio.toggleMusic()
                case "s": audio.toggleEffects()
                case "n", "p":
                    let delta = event.charactersIgnoringModifiers?.lowercased() == "n" ? 1 : -1
                    if mode == .world { try world.nextScenario(delta) } else { try islands.next(delta) }
                    mapScene.show(mode == .world ? world : islands)
                case "d" where mode == .world: buildUI.toggleDemolish()
                case "," where mode == .world: buildUI.rotate(-1)
                case "." where mode == .world: buildUI.rotate(1)
                case "[" where mode == .world: buildUI.cycle(-1)
                case "]" where mode == .world: buildUI.cycle(1)
                case "g" where mode == .world:
                    try world.reroll()
                    mapScene.show(world)
                default: return false
                }
            }
        } catch {
            NSLog("Laden fehlgeschlagen: %@", String(describing: error))
        }
        return true
    }

    private func handleViewerKey(_ event: NSEvent) -> Bool {
        let step = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: moveImage(by: -step)  // ←
        case 124: moveImage(by: step)  // →
        case 125: moveFile(by: 1)  // ↓
        case 126: moveFile(by: -1)  // ↑
        case 116: moveImage(by: -100)  // Bild auf
        case 121: moveImage(by: 100)  // Bild ab
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoom = min(zoom + 1, 8)
            case "-": zoom = max(zoom - 1, 1)
            default: return false
            }
        }
        return true
    }

    /// Ziehen mit der Maus oder Scrollen auf dem Trackpad (Delta in Punkten).
    private func pan(by delta: SIMD2<Float>) {
        guard mode == .world || mode == .island else { return }
        mapScene.pan(by: delta)
    }

    private func moveImage(by delta: Int) {
        guard let count = currentViewerSheet()?.count, count > 0 else { return }
        imageIndex = ((imageIndex + delta) % count + count) % count
    }

    private func moveFile(by delta: Int) {
        fileIndex = ((fileIndex + delta) % bshFiles.count + bshFiles.count) % bshFiles.count
        imageIndex = 0
        viewerSheet = nil
        viewerArchive = nil
    }

    // MARK: Für `--snapshot`

    func showViewer(file: String?, image: Int) {
        mode = .viewer
        if let file, let index = bshFiles.firstIndex(where: { $0.lowercased() == file.lowercased() }) {
            fileIndex = index
            viewerSheet = nil
            viewerArchive = nil
        }
        imageIndex = image
    }

    func showIsland(file: String?, zoom: Int?, rotation: Int?) throws {
        showIslands()
        if let file {
            try islands.select(file: file)
            mapScene.show(islands)
        }
        configureMap(zoom: zoom, rotation: rotation)
    }

    func showWorld(scenario: String?, seed: UInt64?, zoom: Int?, rotation: Int?, panX: Float?, panY: Float?) throws {
        showWorld()
        if let scenario { try world.select(scenario: "Szenes/\(scenario)") }
        if let seed { try world.reroll(seed: seed) }
        mapScene.show(world)
        configureMap(zoom: zoom, rotation: rotation)
        if panX != nil || panY != nil { mapScene.pan(by: SIMD2(panX ?? 0, panY ?? 0)) }
    }

    /// Entwicklerhilfe (`--demo`): Kontor an der nächsten Küste, ein Feldweg, Wohnhäuser, dann Vorschau eines Hauses.
    func buildDemoSettlement() {
        guard let start = world.focus else { return }
        let game = world.game
        guard let kontor = game.buildings[2101], let road = game.buildings[411], let house = game.buildings[605] else { return }
        func nearest(_ type: BuildingType, around c: SIMD2<Float>, radius: Int) -> (x: Int, y: Int)? {
            var best: (Int, Int, Float)?
            for y in Int(c.y) - radius...Int(c.y) + radius {
                for x in Int(c.x) - radius...Int(c.x) + radius {
                    let d = simd_distance(SIMD2(Float(x), Float(y)), c)
                    if best == nil || d < best!.2, world.game.check(type, x: x, y: y, rotation: 0, player: 0).isEmpty {
                        best = (x, y, d)
                    }
                }
            }
            return best.map { ($0.0, $0.1) }
        }
        guard let k = nearest(kontor, around: start, radius: 80) else { return }
        _ = world.mutateGame { $0.build(kontor, x: k.x, y: k.y, rotation: 0, player: 0) }
        let center = SIMD2(Float(k.x), Float(k.y))
        if let r = nearest(road, around: center + SIMD2(3, 3), radius: 8) {
            let path = BuildInterface.roadPath(from: r, to: (r.x + 6, r.y + 4))
            _ = world.mutateGame { $0.buildRoad(road, path: path, player: 0) }
        }
        for _ in 0..<4 {
            if let h = nearest(house, around: center + SIMD2(4, 6), radius: 10) {
                _ = world.mutateGame { $0.build(house, x: h.x, y: h.y, rotation: 0, player: 0) }
            }
        }
        mapScene.show(world)
        mapScene.pan(by: .zero)
        // Vorschau eines weiteren Hauses.
        buildUI.cycle(0)
        _ = buildUI.clickPanel(at: SIMD2(BuildInterface.categoryRects[BuildCategory.housing.rawValue].x + 5, BuildInterface.categoryRects[BuildCategory.housing.rawValue].y + 5))
        buildUI.setHover(nearest(house, around: center + SIMD2(2, 8), radius: 10))
        focusMap(on: center + SIMD2(3, 4))
    }

    func focusMap(on p: SIMD2<Float>) { mapScene.setFocus(p) }

    private func configureMap(zoom: Int?, rotation: Int?) {
        if let zoom, let level = ZoomLevel(rawValue: zoom) { mapScene.setZoom(level) }
        if let rotation { mapScene.rotate(rotation) }
    }
}
