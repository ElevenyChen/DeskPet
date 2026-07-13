import Cocoa

class CatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class DraggableCatView: NSView {
    weak var appDelegate: AppDelegate?
    private var isDragging = false
    private var lastScreenPoint: NSPoint = .zero
    private var mouseDownPoint: NSPoint = .zero
    private var dragConfirmed = false
    private static let dragThreshold: CGFloat = 4

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if appDelegate?.isReminding == true || appDelegate?.isAttacking == true { return }
        isDragging = true
        dragConfirmed = false
        lastScreenPoint = NSEvent.mouseLocation
        mouseDownPoint = lastScreenPoint
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = self.window else { return }
        let current = NSEvent.mouseLocation

        if !dragConfirmed {
            let dx = current.x - mouseDownPoint.x
            let dy = current.y - mouseDownPoint.y
            if sqrt(dx * dx + dy * dy) < DraggableCatView.dragThreshold { return }
            dragConfirmed = true
            appDelegate?.onDragStart()
        }

        let dx = current.x - lastScreenPoint.x
        let dy = current.y - lastScreenPoint.y
        let origin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        lastScreenPoint = current
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        if dragConfirmed {
            appDelegate?.onDragEnd()
        } else {
            appDelegate?.onClicked()
        }
    }
}

class MouseTransparentTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

class MouseTransparentImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            (NSApp.delegate as? AppDelegate)?.dismissHardReminderPublic()
        } else {
            super.keyDown(with: event)
        }
    }
}
