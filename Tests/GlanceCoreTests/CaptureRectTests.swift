import CoreGraphics
import Foundation
import Testing
@testable import GlanceCore

@Suite struct CaptureRectGeometryTests {
    private let screen = CGSize(width: 1440, height: 900)

    @Test func convertsBottomLeftSelectionToTopLeftOrigin() {
        let rect = CaptureRect.fromSelection(CGRect(x: 100, y: 200, width: 400, height: 300), screenSize: screen)
        // Top-left y = 900 − (200 + 300) = 400.
        #expect(rect == CaptureRect(x: 100, y: 400, width: 400, height: 300))
    }

    @Test func aSelectionFlushWithTheTopGetsYZero() {
        let rect = CaptureRect.fromSelection(CGRect(x: 0, y: 800, width: 1440, height: 100), screenSize: screen)
        #expect(rect == CaptureRect(x: 0, y: 0, width: 1440, height: 100))
    }

    @Test func dragDirectionDoesNotMatter() {
        // Dragged up-and-left: negative width/height, same region once standardized.
        let rect = CaptureRect.fromSelection(CGRect(x: 500, y: 500, width: -400, height: -300), screenSize: screen)
        #expect(rect == CaptureRect(x: 100, y: 400, width: 400, height: 300))
    }

    @Test func selectionIsClampedToTheScreen() {
        let rect = CaptureRect.fromSelection(CGRect(x: -50, y: -50, width: 300, height: 400), screenSize: screen)
        // Clipped origin (0,0) size (250,350); top-left y = 900 − 350 = 550.
        #expect(rect == CaptureRect(x: 0, y: 550, width: 250, height: 350))
    }

    @Test func tinySelectionsAreRejected() {
        #expect(CaptureRect.fromSelection(CGRect(x: 10, y: 10, width: 5, height: 300), screenSize: screen) == nil)
        #expect(CaptureRect.fromSelection(CGRect(x: 10, y: 10, width: 0, height: 0), screenSize: screen) == nil)
    }

    @Test func clampKeepsRegionsInsideTheDisplay() {
        let rect = CaptureRect(x: 100, y: 100, width: 400, height: 300)
        #expect(rect.clamped(toWidth: 1440, height: 900) == rect)
        // Partly off a smaller display: kept part only.
        #expect(rect.clamped(toWidth: 300, height: 300) == CaptureRect(x: 100, y: 100, width: 200, height: 200))
    }

    @Test func clampReturnsNilWhenFullyOutside() {
        let rect = CaptureRect(x: 2000, y: 2000, width: 100, height: 100)
        #expect(rect.clamped(toWidth: 1440, height: 900) == nil)
    }
}

@Suite struct CaptureRectConfigTests {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    @Test func defaultHasNoRegion() {
        #expect(AppConfig.default.captureRect == nil)
    }

    @Test func decodesARegion() throws {
        let config = try decode(#"{"captureRect": {"x": 10, "y": 20, "width": 300, "height": 200}}"#)
        #expect(config.captureRect == CaptureRect(x: 10, y: 20, width: 300, height: 200))
    }

    @Test func dropsADegenerateRegion() throws {
        #expect(try decode(#"{"captureRect": {"x": 0, "y": 0, "width": 0, "height": 200}}"#).captureRect == nil)
    }

    @Test func writeCaptureRectRoundTripsAndPreservesOtherKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceHUDTests-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"model": "mine", "fontSize": 14}"#.utf8).write(to: store.fileURL)

        try store.writeCaptureRect(CaptureRect(x: 5, y: 6, width: 100, height: 80))
        var loaded = store.load().config
        #expect(loaded.captureRect == CaptureRect(x: 5, y: 6, width: 100, height: 80))
        #expect(loaded.model == "mine")      // untouched
        #expect(loaded.fontSize == 14)       // untouched

        try store.writeCaptureRect(nil)
        loaded = store.load().config
        #expect(loaded.captureRect == nil)
        #expect(loaded.model == "mine")
    }

    @Test func writeCaptureRectLeavesACorruptFileUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceHUDTests-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"apiKey": "sk-secret", broken"#.utf8).write(to: store.fileURL)

        #expect(throws: (any Error).self) {
            try store.writeCaptureRect(CaptureRect(x: 1, y: 2, width: 3, height: 4))
        }
        // The broken file is left exactly as it was, so a file-stored key is not lost.
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == #"{"apiKey": "sk-secret", broken"#)
    }
}
