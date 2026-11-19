import AppKit
import GlanceCore

/// One-time calibration: a full-screen overlay on the main display where the user drags a rectangle to
/// pick the capture region. Releasing the mouse confirms, Esc cancels. The result is a `CaptureRect`
/// (top-left origin, points), or nil when cancelled.
@MainActor
final class CalibrationController {
    private var window: NSWindow?
    private let screen: NSScreen
    private let onFinish: (CaptureRect?) -> Void

    init(screen: NSScreen, onFinish: @escaping (CaptureRect?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
    }

    func begin() {
        let view = SelectionView(screenSize: screen.frame.size) { [weak self] rect in
            self?.complete(rect)
        }
        let window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false, screen: screen)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = view
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    private func complete(_ rect: CaptureRect?) {
        window?.orderOut(nil)
        window = nil
        onFinish(rect)
    }
}

/// A borderless window has to opt in to becoming key, or it never receives the Esc key press.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    private let screenSize: CGSize
    private let onResult: (CaptureRect?) -> Void
    private var start: NSPoint?
    private var selection: NSRect = .zero

    init(screenSize: CGSize, onResult: @escaping (CaptureRect?) -> Void) {
        self.screenSize = screenSize
        self.onResult = onResult
        super.init(frame: NSRect(origin: .zero, size: screenSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        start = point
        selection = NSRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect = CaptureRect.fromSelection(selection, screenSize: screenSize) {
            onResult(rect)
        } else {
            // Too small to be a real selection; let the user try again.
            start = nil
            selection = .zero
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onResult(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.4).setFill()
        bounds.fill()

        if selection.width > 0, selection.height > 0 {
            // Punch a clear hole so the chosen region shows through unchanged.
            NSColor.clear.set()
            selection.fill(using: .copy)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
            drawLabel("\(Int(selection.width)) × \(Int(selection.height))",
                      at: NSPoint(x: selection.midX, y: selection.maxY + 14), centered: true)
        }
        drawLabel("Yakalanacak bölgeyi sürükleyerek seçin   ·   Esc: iptal",
                  at: NSPoint(x: bounds.midX, y: bounds.maxY - 60), centered: true)
    }

    private func drawLabel(_ text: String, at point: NSPoint, centered: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black
                shadow.shadowBlurRadius = 3
                return shadow
            }(),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        var origin = point
        if centered { origin.x -= string.size().width / 2 }
        string.draw(at: origin)
    }
}
