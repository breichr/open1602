import AnnoFormats
import Metal
import simd

/// Abbildung von virtuellen Spielpixeln (y nach unten) auf Drawable-Pixel.
public struct ViewTransform: Sendable, Equatable {
    public var drawableSize: SIMD2<Float>
    public var scale: Float
    public var offset: SIMD2<Float>

    public init(drawableSize: SIMD2<Float>, scale: Float, offset: SIMD2<Float> = .zero) {
        self.drawableSize = drawableSize
        self.scale = scale
        self.offset = offset
    }

    /// Skaliert `virtualSize` seitenverhältnistreu in das Drawable und zentriert es (Letterbox).
    public static func fit(virtualSize: SIMD2<Float>, drawableSize: SIMD2<Float>) -> ViewTransform {
        let scale = min(drawableSize.x / virtualSize.x, drawableSize.y / virtualSize.y)
        let offset = ((drawableSize - virtualSize * scale) / 2).rounded(.down)
        return ViewTransform(drawableSize: drawableSize, scale: scale, offset: offset)
    }
}

/// Ein Sprite aus einem `SpriteSheet` an einer Position (linke obere Ecke, virtuelle Pixel).
public struct SpriteDraw: Sendable, Equatable {
    public var index: Int
    public var position: SIMD2<Float>

    public init(index: Int, position: SIMD2<Float>) {
        self.index = index
        self.position = position
    }
}

/// Zeichnet palettenindizierte Sprites mit Metal.
public final class SpriteRenderer {
    public let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private var paletteTexture: MTLTexture?

    /// Layout muss zu `Instance` im Shader passen.
    private struct SpriteInstance {
        var dst: SIMD4<Float>
        var src: SIMD4<Float>
        var extra: SIMD4<UInt32>
    }

    /// Höchstzahl gleichzeitig gebundener Atlasseiten (muss zu `MAX_PAGES` im Shader passen).
    public static let maxPages = 16

    /// Layout muss zu `Uniforms` im Shader passen.
    private struct ViewUniforms {
        var drawableSize: SIMD2<Float>
        var offset: SIMD2<Float>
        var scale: Float
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case noMetalDevice
        case textureCreationFailed

        public var description: String {
            switch self {
            case .noMetalDevice: "Kein Metal-Gerät gefunden"
            case .textureCreationFailed: "Palettentextur konnte nicht angelegt werden"
            }
        }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        let library = try device.makeLibrary(source: Shaders.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Sprites"
        descriptor.vertexFunction = library.makeFunction(name: "sprite_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "sprite_fragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    public func setPalette(_ palette: Palette) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 256, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Error.textureCreationFailed }
        let bytes = palette.colors.flatMap { color -> [UInt8] in [color.r, color.g, color.b, 255] }
        texture.replace(region: MTLRegionMake2D(0, 0, 256, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 256 * 4)
        paletteTexture = texture
    }

    public func draw(
        _ sprites: [SpriteDraw], from sheet: SpriteSheet, transform: ViewTransform,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let paletteTexture, !sprites.isEmpty, !sheet.pages.isEmpty else { return }
        precondition(sheet.pages.count <= Self.maxPages, "Zu viele Atlasseiten (\(sheet.pages.count))")

        // Reihenfolge bleibt erhalten: ein Draw-Call für alle Sprites, Seite pro Instanz.
        var instances: [SpriteInstance] = []
        instances.reserveCapacity(sprites.count)
        for sprite in sprites {
            let p = sheet.placements[sprite.index]
            guard p.width > 0 else { continue }
            let size = SIMD2<Float>(Float(p.width), Float(p.height))
            instances.append(SpriteInstance(
                dst: SIMD4(lowHalf: sprite.position, highHalf: size),
                src: SIMD4(Float(p.x), Float(p.y), size.x, size.y),
                extra: SIMD4(UInt32(p.page), 0, 0, 0)))
        }
        guard !instances.isEmpty else { return }

        var uniforms = ViewUniforms(drawableSize: transform.drawableSize, offset: transform.offset, scale: transform.scale)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        let pages = (0..<Self.maxPages).map { sheet.pages[min($0, sheet.pages.count - 1)] }
        encoder.setFragmentTextures(pages, range: 0..<Self.maxPages)
        encoder.setFragmentTexture(paletteTexture, index: Self.maxPages)

        let length = MemoryLayout<SpriteInstance>.stride * instances.count
        if length <= 4096 {
            instances.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: length, index: 0) }
        } else {
            guard let buffer = instances.withUnsafeBytes({
                device.makeBuffer(bytes: $0.baseAddress!, length: length, options: .storageModeShared)
            }) else { return }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
    }
}
