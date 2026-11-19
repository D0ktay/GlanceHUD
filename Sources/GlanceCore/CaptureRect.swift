import CoreGraphics
import Foundation

/// A sub-region of the main display to capture instead of the whole screen.
/// Points, origin at the display's TOP-left — the space ScreenCaptureKit's `sourceRect` uses.
public struct CaptureRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Turns a rectangle the user dragged in AppKit screen coordinates (origin BOTTOM-left) into a
    /// top-left-origin rect, clamped to the display. Returns nil for a selection smaller than `minSize`
    /// on either side — a stray click, treated as "nothing selected".
    public static func fromSelection(_ selection: CGRect, screenSize: CGSize, minSize: Double = 20) -> CaptureRect? {
        let clamped = selection.standardized.intersection(CGRect(origin: .zero, size: screenSize))
        guard clamped.width >= minSize, clamped.height >= minSize else { return nil }
        let topLeftY = Double(screenSize.height) - Double(clamped.maxY)
        return CaptureRect(
            x: Double(clamped.origin.x).rounded(),
            y: topLeftY.rounded(),
            width: Double(clamped.width).rounded(),
            height: Double(clamped.height).rounded()
        )
    }

    /// The part of this rect that lies inside a `width`×`height` display, or nil if it falls outside or is
    /// degenerate — e.g. the display's size or resolution changed since calibration.
    public func clamped(toWidth width: Double, height: Double) -> CaptureRect? {
        let clipped = cgRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }
        return CaptureRect(x: Double(clipped.origin.x), y: Double(clipped.origin.y),
                           width: Double(clipped.width), height: Double(clipped.height))
    }
}
