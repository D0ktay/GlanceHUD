import CoreGraphics

public enum HUDLayout {
    public static let margin: CGFloat = 20
    public static let padding: CGFloat = 14
    /// Small inset so glyphs never touch the window edge when there is no box.
    public static let textOnlyPadding: CGFloat = 6
    public static let gap: CGFloat = 8

    /// Bottom-right corner of `visibleFrame` (AppKit coordinates, origin bottom-left), inset by `margin`
    /// and shrunk if needed so the window never leaves the visible area.
    public static func frame(size: CGSize, visibleFrame: CGRect, margin: CGFloat = margin) -> CGRect {
        let width = min(size.width, max(visibleFrame.width - 2 * margin, 0))
        let height = min(size.height, max(visibleFrame.height - 2 * margin, 0))
        return CGRect(
            x: visibleFrame.maxX - margin - width,
            y: visibleFrame.minY + margin,
            width: width,
            height: height
        )
    }

    /// The body text may use up to 70% of the visible height, minus the window chrome.
    public static func maxBodyHeight(visibleHeight: CGFloat, chrome: CGFloat) -> CGFloat {
        max(visibleHeight * 0.7 - chrome, 40)
    }
}
