import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageSizing {
    /// Scales a pixel size down so its longer side is at most `maxLongEdge`, keeping the aspect ratio.
    /// Never upscales.
    public static func fit(width: Int, height: Int, maxLongEdge: Int) -> (width: Int, height: Int) {
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge, maxLongEdge > 0 else { return (max(width, 1), max(height, 1)) }
        let scale = Double(maxLongEdge) / Double(longEdge)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }
}

public enum JPEGEncoder {
    public static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw GlanceError.captureFailed("JPEG kodlayıcı açılamadı")
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw GlanceError.captureFailed("JPEG yazılamadı")
        }
        return data as Data
    }
}
