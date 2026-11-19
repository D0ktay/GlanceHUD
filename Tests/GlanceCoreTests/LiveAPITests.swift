import CoreGraphics
import Foundation
import Testing
@testable import GlanceCore

/// One real API request through the app's own request/stream code, using a generated image (no screen content).
/// Off by default because it costs a fraction of a cent:
///   GLANCE_LIVE_TEST=1 ANTHROPIC_API_KEY=... swift test --filter LiveAPITests
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["GLANCE_LIVE_TEST"] == "1"),
    .timeLimit(.minutes(2))
)
struct LiveAPITests {
    @Test func realRequestStreamsAnAnswer() async throws {
        let apiKey = try #require(ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"])
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let jpeg = try JPEGEncoder.encode(try #require(context.makeImage()), quality: 0.85)

        var config = AppConfig.default
        config.prompt = "Bu görüntü ne renk? Tek kelimeyle yanıtla."

        var accumulator = StreamAccumulator()
        for try await event in ClaudeClient().stream(imageJPEG: jpeg, config: config, apiKey: apiKey) {
            accumulator.apply(event)
        }
        print("LIVE model=\(accumulator.model ?? "?") outcome=\(accumulator.outcome)")
        guard case .completed(let text, _) = accumulator.outcome else {
            Issue.record("unexpected outcome: \(accumulator.outcome)")
            return
        }
        #expect(text.lowercased().contains("kırmızı"))
    }
}
