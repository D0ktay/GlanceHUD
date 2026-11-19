import CoreGraphics
import Foundation
import GlanceCore
import ScreenCaptureKit

/// Grabs the main display with ScreenCaptureKit (`CGWindowListCreateImage` is obsolete on current macOS),
/// leaving out this app's own windows.
struct ScreenCapturer: ScreenCapturing {
    /// The HUD stays hidden while capturing, so a stalled capture must end in a visible error.
    private static let timeoutSeconds: Double = 15

    func captureJPEG(maxLongEdge: Int, quality: Double, cropRect: CaptureRect?) async throws -> Data {
        try await withTimeout(
            seconds: Self.timeoutSeconds,
            timeoutError: .captureFailed("\(Int(Self.timeoutSeconds)) saniye içinde tamamlanmadı")
        ) {
            try await Self.capture(maxLongEdge: maxLongEdge, quality: quality, cropRect: cropRect)
        }
    }

    private static func capture(maxLongEdge: Int, quality: Double, cropRect: CaptureRect?) async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else {
            // Shows the system prompt the first time; the user must relaunch after granting.
            CGRequestScreenCaptureAccess()
            throw GlanceError.screenPermissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw GlanceError.captureFailed(error.localizedDescription)
        }
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw GlanceError.captureFailed("ekran bulunamadı")
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = CGFloat(filter.pointPixelScale)
        let displaySize = filter.contentRect.size
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false

        // A calibrated region crops the capture; without one (or if it no longer fits the display) the
        // whole display is captured.
        let regionPoints: CGSize
        if let crop = cropRect?.clamped(toWidth: Double(displaySize.width), height: Double(displaySize.height)) {
            configuration.sourceRect = crop.cgRect // points, top-left origin within the display
            regionPoints = crop.cgRect.size
        } else {
            regionPoints = displaySize
        }
        let size = ImageSizing.fit(
            width: Int(regionPoints.width * scale),
            height: Int(regionPoints.height * scale),
            maxLongEdge: maxLongEdge
        )
        configuration.width = size.width
        configuration.height = size.height

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw GlanceError.captureFailed(error.localizedDescription)
        }
        return try JPEGEncoder.encode(image, quality: quality)
    }
}
