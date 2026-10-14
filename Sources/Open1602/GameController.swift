import AnnoFormats
import AnnoRender
import AppKit
import MetalKit

/// Steuert, was die App anzeigt: Startbildschirm, Inselansicht oder BSH-Viewer (Tab wechselt).
@MainActor
final class GameController: NSObject, MTKViewDelegate, NSWindowDelegate {
    enum Mode {
        /// Startbildschirm, 1024×768 seitenverhältnistreu ins Fenster skaliert.
        case title
        /// Inselansicht: Pfeiltasten/Ziehen scrollen, +/− Zoom, R drehen, N/P Insel.
        case island
        /// Sprite-Browser: ←/→ Bild, ↑/↓ Datei, +/− Zoom.
        case viewer
    }

    private let gameData: GameData
    private let view: GameView
    private let commandQueue: MTLCommandQueue
    private let renderer: SpriteRenderer

    private var mode: Mode = .title
    private let titleSheet: SpriteSheet
    private let islandScene: IslandScene

    private let bshFiles: [String]
    private var fileIndex: Int
    private var imageIndex = 0
    private var zoom: Float = 2
    private var viewerSheet: SpriteSheet?
    private var viewerArchive: BSHArchive?

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
        // Neu zeichnen nur bei Änderungen; die Spielschleife kommt in späteren Meilensteinen.
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        renderer = try SpriteRenderer(device: device, pixelFormat: view.colorPixelFormat)
        try renderer.setPalette(Palette(colFile: gameData.read("ToolGfx/STADTFLD.COL")))
        titleSheet = try SpriteSheet(device: device, archive: BSHArchive(fileBytes: gameData.read("ToolGfx/START.BSH")))
        islandScene = try IslandScene(gameData: gameData, device: device)

        bshFiles = gameData.files(withExtension: "bsh")
        fileIndex = bshFiles.firstIndex { $0.lowercased() == "gfx/stadtfld.bsh" } ?? 0
        super.init()
        view.delegate = self
        view.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        view.onPan = { [weak self] delta in self?.pan(by: delta) }
    }

    // MARK: Darstellung

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.needsDisplay = true
    }

    func draw(in view: MTKView) {
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
    }

    private func encodeScene(encoder: MTLRenderCommandEncoder, drawableSize: SIMD2<Float>, backingScale: Float) {
        switch mode {
        case .title:
            let transform = ViewTransform.fit(virtualSize: Self.titleSize, drawableSize: drawableSize)
            renderer.draw([SpriteDraw(index: 0, position: .zero)], from: titleSheet, transform: transform, encoder: encoder)
        case .island:
            islandScene.draw(renderer: renderer, encoder: encoder, drawableSize: drawableSize, backingScale: backingScale)
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

    /// Für `--snapshot`: Modus und Viewer-Position setzen.
    func showViewer(file: String?, image: Int) {
        mode = .viewer
        if let file, let index = bshFiles.firstIndex(where: { $0.lowercased() == file.lowercased() }) {
            fileIndex = index
            viewerSheet = nil
            viewerArchive = nil
        }
        imageIndex = image
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
        switch mode {
        case .title:
            view.window?.title = "Open1602  ·  Tab: Inseln / Sprite-Viewer"
        case .island:
            view.window?.title = "\(islandScene.title)  ·  ←↑→↓ Scrollen  +− Zoom  R Drehen  N/P Insel"
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
            mode = switch mode {
            case .title: .island
            case .island: .viewer
            case .viewer: .title
            }
        } else {
            let handled = switch mode {
            case .title: false
            case .island: handleIslandKey(event)
            case .viewer: handleViewerKey(event)
            }
            guard handled else { return false }
        }
        updateTitle()
        view.needsDisplay = true
        return true
    }

    private func handleIslandKey(_ event: NSEvent) -> Bool {
        let step: Float = event.modifierFlags.contains(.shift) ? 400 : 100
        do {
            switch event.keyCode {
            case 123: islandScene.pan(by: SIMD2(-step, 0))  // ←
            case 124: islandScene.pan(by: SIMD2(step, 0))  // →
            case 125: islandScene.pan(by: SIMD2(0, step))  // ↓
            case 126: islandScene.pan(by: SIMD2(0, -step))  // ↑
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "+", "=": islandScene.setZoom(ZoomLevel(rawValue: islandScene.zoom.rawValue - 1) ?? .large)
                case "-": islandScene.setZoom(ZoomLevel(rawValue: islandScene.zoom.rawValue + 1) ?? .small)
                case "r": islandScene.rotate(event.modifierFlags.contains(.shift) ? -1 : 1)
                case "n": try islandScene.nextIsland(1)
                case "p": try islandScene.nextIsland(-1)
                default: return false
                }
            }
        } catch {
            NSLog("Insel konnte nicht geladen werden: %@", String(describing: error))
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
        guard mode == .island else { return }
        islandScene.pan(by: delta)
        view.needsDisplay = true
    }

    /// Für `--snapshot`: Inselansicht einstellen.
    func showIsland(file: String?, zoom: Int?, rotation: Int?) throws {
        mode = .island
        if let file { try islandScene.select(file: file) }
        if let zoom, let level = ZoomLevel(rawValue: zoom) { islandScene.setZoom(level) }
        if let rotation { islandScene.rotate(rotation) }
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
}
