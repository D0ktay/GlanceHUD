import AppKit
import GlanceCore

/// Borderless panel that floats over everything, never takes focus and lets clicks fall through.
final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Ask the window server to leave this window out of screenshots and screen recordings.
        sharingType = .none
        hidesOnDeactivate = false
        // "Hide Others" in another app can hide accessory apps too; an app that never activates
        // would never be unhidden, so the panel opts out of hiding.
        canHide = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content view. With `drawsBox` it paints the semi-transparent dark rounded backdrop; otherwise it is
/// fully transparent and only the text shows. Drawn in `draw(_:)` rather than with layer properties
/// so `--snapshot` renders it too.
final class HUDBackdropView: NSView {
    var drawsBox = false

    override func draw(_ dirtyRect: NSRect) {
        guard drawsBox else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.07, alpha: 0.84).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
final class HUDWindowController: HUDDisplaying {
    private let panel = HUDPanel()
    private let backdrop = HUDBackdropView()
    private let bodyField = NSTextField(wrappingLabelWithString: "")
    private let footerField = NSTextField(labelWithString: "")
    private let style: @MainActor () -> AppConfig
    private var content = HUDContent.empty
    private var screenObserver: NSObjectProtocol?

    init(style: @escaping @MainActor () -> AppConfig) {
        self.style = style
        panel.contentView = backdrop

        bodyField.isSelectable = false
        bodyField.maximumNumberOfLines = 0
        bodyField.lineBreakMode = .byWordWrapping
        bodyField.cell?.truncatesLastVisibleLine = true
        footerField.lineBreakMode = .byTruncatingTail
        backdrop.addSubview(bodyField)
        backdrop.addSubview(footerField)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func render(_ content: HUDContent) {
        self.content = content
        layout()
    }

    /// Lays the current content out again after a style change (e.g. a new font size).
    func restyle() {
        layout()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if NSApp.isHidden { NSApp.unhideWithoutActivation() }
            layout()
            // Draw the new text before the window comes up, so the previous answer never flashes.
            panel.displayIfNeeded()
            // Unlike makeKeyAndOrderFront, this shows the panel without activating the app,
            // so keyboard focus stays in whatever the user is working in.
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Renders the HUD as it would currently appear, once over a white and once over a dark background,
    /// without needing Screen Recording permission.
    func snapshotPNG() -> Data? {
        layout()
        guard let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return nil }
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)

        let inset: CGFloat = 20
        let tile = NSSize(width: backdrop.bounds.width + 2 * inset, height: backdrop.bounds.height + 2 * inset)
        let image = NSImage(size: NSSize(width: tile.width, height: tile.height * 2), flipped: false) { _ in
            for (index, shade) in [CGFloat(1), 0.16].enumerated() {
                let origin = NSPoint(x: 0, y: CGFloat(index) * tile.height)
                NSColor(calibratedWhite: shade, alpha: 1).setFill()
                NSRect(origin: origin, size: tile).fill()
                rep.draw(in: NSRect(x: inset, y: origin.y + inset,
                                    width: self.backdrop.bounds.width, height: self.backdrop.bounds.height),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func layout() {
        // screens[0] holds the menu bar: the main display, the same one ScreenCapturer grabs.
        guard let screen = NSScreen.screens.first else { return }
        let config = style()
        let boxed = config.showBox
        let padding = boxed ? HUDLayout.padding : HUDLayout.textOnlyPadding
        // Measure at the width the window will really get, or a hudWidth wider than the screen
        // would re-wrap the text into more lines than were measured and cut off the last one.
        let windowWidth = min(CGFloat(config.hudWidth), screen.visibleFrame.width - 2 * HUDLayout.margin)
        let maxTextWidth = windowWidth - 2 * padding

        bodyField.attributedStringValue = bodyText(config: config, boxed: boxed)
        footerField.isHidden = !boxed
        footerField.font = .monospacedSystemFont(ofSize: max(config.fontSize - 3, min(9, config.fontSize)), weight: .regular)
        footerField.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        footerField.stringValue = content.footer

        let footerHeight = boxed ? ceil(footerField.cell?.cellSize.height ?? 12) : 0
        let chrome = 2 * padding + (boxed ? HUDLayout.gap + footerHeight : 0)
        let measured = bodyField.cell?.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: maxTextWidth, height: .greatestFiniteMagnitude)
        ) ?? .zero
        let bodyHeight = min(ceil(measured.height),
                             HUDLayout.maxBodyHeight(visibleHeight: screen.visibleFrame.height, chrome: chrome))

        // Fixed width: hugging the text made it slide left while the first line streamed in, and with a
        // transparent background the unused width is invisible anyway.
        let frame = HUDLayout.frame(
            size: CGSize(width: windowWidth, height: bodyHeight + chrome),
            visibleFrame: screen.visibleFrame
        )
        panel.hasShadow = boxed
        panel.setFrame(frame, display: false)
        backdrop.drawsBox = boxed
        backdrop.frame = NSRect(origin: .zero, size: frame.size)
        let innerWidth = frame.width - 2 * padding
        footerField.frame = NSRect(x: padding, y: padding, width: innerWidth, height: footerHeight)
        bodyField.frame = NSRect(
            x: padding, y: padding + (boxed ? footerHeight + HUDLayout.gap : 0),
            width: innerWidth, height: frame.height - chrome
        )
        backdrop.needsDisplay = true
        if boxed { panel.invalidateShadow() }
    }

    /// Light text on the dark box, or (without the box) plain see-through gray that stays out of the way.
    private func bodyText(config: AppConfig, boxed: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let color = boxed
            ? NSColor(calibratedWhite: content.isPlaceholder ? 0.62 : 0.93, alpha: 1)
            : NSColor(calibratedWhite: config.textGray,
                      alpha: config.textOpacity * (content.isPlaceholder ? 0.7 : 1))
        return NSAttributedString(string: content.body, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: config.fontSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }
}
