import AppKit

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Pixel-accurate hit testing

/// Captures a 1×1 pixel from the composited window image at the given CG-coordinate point.
///
/// `CGWindowListCreateImage` is deprecated in macOS 14 in favour of `ScreenCaptureKit`.
/// However, `SCScreenshotManager` is async-only and cannot be used inside the synchronous
/// `hitTest(_:)` override below. We isolate the deprecated call in this helper so the
/// deprecation warning is suppressed in exactly one place and is easy to replace when
/// Apple provides a synchronous SCK capture path.
@available(macOS, deprecated: 14.0, message: "Replace with ScreenCaptureKit when a sync API is available.")
private func sampleWindowAlpha(windowID: CGWindowID, at cgPoint: CGPoint) -> UInt8 {
    let captureRect = CGRect(x: cgPoint.x - 0.5, y: cgPoint.y - 0.5, width: 1, height: 1)
    guard let image = CGWindowListCreateImage(
        captureRect,
        .optionIncludingWindow,
        windowID,
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return 0 }

    var pixel: [UInt8] = [0, 0, 0, 0]
    guard let ctx = CGContext(
        data: &pixel, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }

    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return pixel[3]
}

class CharacterContentView: NSView {
    weak var character: WalkerCharacter?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
        // NSScreen origin is bottom-left of the primary display; CG origin is top-left.
        // Use the primary screen height as the flip basis so multi-monitor positions are correct.
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let cgPoint = CGPoint(x: screenPoint.x, y: primaryScreen.frame.height - screenPoint.y)

        if let windowID = window?.windowNumber, windowID > 0 {
            let alpha = sampleWindowAlpha(windowID: CGWindowID(windowID), at: cgPoint)
            return alpha > 30 ? self : nil
        }

        // Fallback: accept click if within center 60% of the view
        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.15
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint) ? self : nil
    }

    // MARK: - Drag-to-reposition support

    private var dragStartPoint: NSPoint?
    private var windowStartOrigin: NSPoint?
    private var isDragging = false
    private static let dragThreshold: CGFloat = 5

    override func mouseDown(with event: NSEvent) {
        guard WalkerCharacter.dragEnabled else {
            character?.handleClick()
            return
        }
        dragStartPoint = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard WalkerCharacter.dragEnabled,
              let startPoint = dragStartPoint,
              let startOrigin = windowStartOrigin else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y

        if !isDragging && (abs(dx) > Self.dragThreshold || abs(dy) > Self.dragThreshold) {
            isDragging = true
            character?.startDrag()
        }

        if isDragging {
            window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
            character?.trackDragVelocity()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard WalkerCharacter.dragEnabled else { return }
        if !isDragging {
            character?.handleClick()
        } else {
            character?.endDrag()
        }
        isDragging = false
        dragStartPoint = nil
        windowStartOrigin = nil
    }
}

