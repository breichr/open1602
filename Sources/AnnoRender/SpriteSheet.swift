import AnnoFormats
import Metal

/// Alle Bilder eines BSH-Archivs als indizierte Atlastexturen auf der GPU.
///
/// Texelformat `rg8Uint`: R = Palettenindex, G = 1 für deckende Pixel.
/// Die Palette wird erst im Shader angewendet (Spielerfarben, Palettenanimation).
public final class SpriteSheet {
    public let pages: [MTLTexture]
    public let placements: [AtlasPlacement]

    public var count: Int { placements.count }

    public enum Error: Swift.Error, CustomStringConvertible {
        case textureCreationFailed

        public var description: String { "Atlastextur konnte nicht angelegt werden" }
    }

    public init(device: MTLDevice, images: [IndexedImage], packer: AtlasPacker = AtlasPacker()) throws {
        let packed = try packer.pack(sizes: images.map { ($0.width, $0.height) })
        let width = packer.pageSize
        var buffers = packed.pageHeights.map { [UInt8](repeating: 0, count: width * $0 * 2) }

        for (image, place) in zip(images, packed.placements) where place.width > 0 {
            buffers[place.page].withUnsafeMutableBufferPointer { page in
                for row in 0..<image.height {
                    var dst = ((place.y + row) * width + place.x) * 2
                    var src = row * image.width
                    for _ in 0..<image.width {
                        page[dst] = image.indices[src]
                        page[dst + 1] = image.opaque[src] ? 1 : 0
                        dst += 2
                        src += 1
                    }
                }
            }
        }

        pages = try zip(packed.pageHeights, buffers).map { height, bytes in
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rg8Uint, width: width, height: max(height, 1), mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw Error.textureCreationFailed }
            if height > 0 {
                bytes.withUnsafeBytes { raw in
                    texture.replace(
                        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: width * 2)
                }
            }
            return texture
        }
        placements = packed.placements
    }

    /// Dekodiert alle Bilder des Archivs und lädt sie hoch.
    public convenience init(device: MTLDevice, archive: BSHArchive) throws {
        let images = try (0..<archive.count).map { try archive.image(at: $0) }
        try self.init(device: device, images: images)
    }
}
