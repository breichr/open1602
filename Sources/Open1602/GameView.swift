import AppKit
import MetalKit

/// Metal-View, die Tastatureingaben an den Controller weiterreicht.
final class GameView: MTKView {
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Verschiebung der Kamera in Punkten (Ziehen, Trackpad, Mausrad).
    var onPan: ((SIMD2<Float>) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        onPan?(SIMD2(Float(-event.deltaX), Float(-event.deltaY)))
    }

    override func scrollWheel(with event: NSEvent) {
        let factor: Float = event.hasPreciseScrollingDeltas ? 1 : 10
        onPan?(SIMD2(Float(-event.scrollingDeltaX), Float(-event.scrollingDeltaY)) * factor)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
