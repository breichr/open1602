import AppKit
import MetalKit

/// Metal-View, die Tastatureingaben an den Controller weiterreicht.
final class GameView: MTKView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
