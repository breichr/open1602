import AnnoFormats
import Foundation
import Metal
import Testing

@testable import AnnoRender

/// Rendert offscreen und vergleicht pixelgenau mit der CPU-Dekodierung.
@Suite("SpriteRenderer")
struct RenderTests {
    static let device = MTLCreateSystemDefaultDevice()

    static let gameData: GameData? = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try? GameData.locate(currentDirectory: repoRoot)
    }()

    /// Rendert `sprites` in eine BGRA-Textur und liefert die Pixel.
    func render(
        _ sprites: [SpriteDraw], sheet: SpriteSheet, palette: Palette, width: Int, height: Int, scale: Float = 1
    ) throws -> [UInt8] {
        let device = try #require(Self.device)
        let renderer = try SpriteRenderer(device: device, pixelFormat: .bgra8Unorm)
        try renderer.setPalette(palette)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        let queue = try #require(device.makeCommandQueue())
        let commands = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commands.makeRenderCommandEncoder(descriptor: pass))
        renderer.draw(
            sprites, from: sheet,
            transform: ViewTransform(drawableSize: SIMD2(Float(width), Float(height)), scale: scale),
            encoder: encoder)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    @Test(.enabled(if: device != nil)) func syntheticSpriteWithTransparencyAndScale() throws {
        var image = IndexedImage(width: 2, height: 1, type: 1)
        image.indices = [5, 0]
        image.opaque = [true, false]
        var colors = [RGBColor](repeating: RGBColor(r: 0, g: 0, b: 0), count: 256)
        colors[5] = RGBColor(r: 200, g: 100, b: 50)
        let sheet = try SpriteSheet(device: Self.device!, images: [image])

        let pixels = try render(
            [SpriteDraw(index: 0, position: SIMD2(1, 0))], sheet: sheet, palette: Palette(colors: colors),
            width: 6, height: 2, scale: 2)
        func bgra(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[(y * 6 + x) * 4..<(y * 6 + x) * 4 + 4]) }
        // Sprite liegt bei virtuell x = 1 → Drawable x = 2..3 (deckend), 4..5 (transparent).
        #expect(bgra(1, 0) == [0, 0, 0, 0])
        #expect(bgra(2, 0) == [50, 100, 200, 255])
        #expect(bgra(3, 1) == [50, 100, 200, 255])
        #expect(bgra(4, 0) == [0, 0, 0, 0])
    }

    @Test(.enabled(if: device != nil && gameData != nil)) func startScreenMatchesCPUDecoding() throws {
        let data = try #require(Self.gameData)
        let palette = try Palette(colFile: data.read("ToolGfx/STADTFLD.COL"))
        let archive = try BSHArchive(fileBytes: data.read("ToolGfx/START.BSH"))
        let sheet = try SpriteSheet(device: Self.device!, archive: archive)
        let image = try archive.image(at: 0)

        let pixels = try render(
            [SpriteDraw(index: 0, position: .zero)], sheet: sheet, palette: palette,
            width: image.width, height: image.height)
        let expected = image.rgba(palette: palette)
        var mismatches = 0
        for i in 0..<(image.width * image.height) {
            let gpu = (pixels[i * 4 + 2], pixels[i * 4 + 1], pixels[i * 4], pixels[i * 4 + 3])
            let cpu = (expected[i * 4], expected[i * 4 + 1], expected[i * 4 + 2], expected[i * 4 + 3])
            if gpu != cpu { mismatches += 1 }
        }
        #expect(mismatches == 0)
    }

    @Test(.enabled(if: device != nil && gameData != nil)) func stadtfeldFitsIntoFewPages() throws {
        let data = try #require(Self.gameData)
        let sheet = try SpriteSheet(device: Self.device!, archive: BSHArchive(fileBytes: data.read("GFX/STADTFLD.BSH")))
        #expect(sheet.count == 5748)
        #expect(sheet.pages.count <= 4)
    }
}

extension RenderTests {
    /// Sprites auf verschiedenen Atlasseiten müssen in Aufrufreihenfolge gezeichnet werden.
    @Test(.enabled(if: device != nil)) func drawOrderAcrossAtlasPages() throws {
        func solid(_ index: UInt8) -> IndexedImage {
            var image = IndexedImage(width: 4, height: 4, type: 1)
            image.indices = Array(repeating: index, count: 16)
            image.opaque = Array(repeating: true, count: 16)
            return image
        }
        var colors = [RGBColor](repeating: RGBColor(r: 0, g: 0, b: 0), count: 256)
        colors[1] = RGBColor(r: 255, g: 0, b: 0)
        colors[2] = RGBColor(r: 0, g: 255, b: 0)
        // Seitengröße 4 → jedes Bild landet auf einer eigenen Seite.
        let sheet = try SpriteSheet(device: Self.device!, images: [solid(1), solid(2)], packer: AtlasPacker(pageSize: 4))
        #expect(sheet.pages.count == 2)
        let palette = Palette(colors: colors)
        let greenOnTop = try render(
            [SpriteDraw(index: 1, position: .zero), SpriteDraw(index: 0, position: .zero)],
            sheet: sheet, palette: palette, width: 4, height: 4)
        #expect(Array(greenOnTop[0..<4]) == [0, 0, 255, 255])
        let redOnTop = try render(
            [SpriteDraw(index: 0, position: .zero), SpriteDraw(index: 1, position: .zero)],
            sheet: sheet, palette: palette, width: 4, height: 4)
        #expect(Array(redOnTop[0..<4]) == [0, 255, 0, 255])
    }
}
