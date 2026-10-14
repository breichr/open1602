import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGWriter {
    struct WriteError: Error, CustomStringConvertible {
        let url: URL
        var description: String { "PNG konnte nicht geschrieben werden: \(url.path)" }
    }

    /// Schreibt nicht vormultiplizierte RGBA-Pixel als PNG.
    static func write(rgba: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard
            let provider = CGDataProvider(data: Data(rgba) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WriteError(url: url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WriteError(url: url) }
    }
}
