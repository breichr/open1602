import AppKit
import MetalKit

/// Metal-View, die Tastatureingaben an den Controller weiterreicht.
final class GameView: MTKView {
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Verschiebung der Kamera in Punkten (Ziehen, Trackpad, Mausrad).
    var onPan: ((SIMD2<Float>) -> Void)?
    /// Mausereignisse mit Position in Punkten (Ursprung oben links).
    var onMouse: ((MouseEvent, SIMD2<Float>) -> Void)?

    enum MouseEvent {
        case moved, down, dragged, up, rightDown
    }

    private func point(_ event: NSEvent) -> SIMD2<Float> {
        let p = convert(event.locationInWindow, from: nil)
        return SIMD2(Float(p.x), Float(bounds.height - p.y))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { onMouse?(.moved, point(event)) }
    override func mouseDown(with event: NSEvent) { onMouse?(.down, point(event)) }
    override func mouseUp(with event: NSEvent) { onMouse?(.up, point(event)) }
    override func rightMouseDown(with event: NSEvent) { onMouse?(.rightDown, point(event)) }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        onMouse?(.dragged, point(event))
    }

    override func rightMouseDragged(with event: NSEvent) {
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
