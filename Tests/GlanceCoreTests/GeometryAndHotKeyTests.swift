import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GlanceCore

@Suite struct ImageTests {
    @Test func downscalesLongEdgeKeepingAspect() {
        #expect(ImageSizing.fit(width: 2880, height: 1800, maxLongEdge: 2048) == (2048, 1280))
        #expect(ImageSizing.fit(width: 1800, height: 2880, maxLongEdge: 2048) == (1280, 2048))
        #expect(ImageSizing.fit(width: 5120, height: 1440, maxLongEdge: 2048) == (2048, 576))
    }

    @Test func neverUpscales() {
        #expect(ImageSizing.fit(width: 1440, height: 900, maxLongEdge: 2048) == (1440, 900))
        #expect(ImageSizing.fit(width: 2048, height: 1000, maxLongEdge: 2048) == (2048, 1000))
    }

    @Test func encodesDecodableJPEG() throws {
        let context = try #require(CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        let image = try #require(context.makeImage())

        let data = try JPEGEncoder.encode(image, quality: 0.85)
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 64)
        #expect(decoded.height == 40)
    }
}

@Suite struct HUDLayoutTests {
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 850)

    @Test func sitsInBottomRightCorner() {
        let frame = HUDLayout.frame(size: CGSize(width: 480, height: 120), visibleFrame: visible)
        #expect(frame == CGRect(x: 1440 - 20 - 480, y: 25 + 20, width: 480, height: 120))
    }

    @Test func respectsOffsetScreensAndDock() {
        let secondary = CGRect(x: -1920, y: 80, width: 1920, height: 1000)
        let frame = HUDLayout.frame(size: CGSize(width: 400, height: 100), visibleFrame: secondary)
        #expect(frame.maxX == secondary.maxX - 20)
        #expect(frame.minY == secondary.minY + 20)
    }

    @Test func neverLeavesTheVisibleArea() {
        let frame = HUDLayout.frame(size: CGSize(width: 5000, height: 5000), visibleFrame: visible)
        #expect(visible.contains(frame))
        #expect(frame.width == 1400)
        #expect(frame.height == 810)
    }

    @Test func bodyHeightIsCappedButNeverTiny() {
        #expect(HUDLayout.maxBodyHeight(visibleHeight: 1000, chrome: 50) == 650)
        #expect(HUDLayout.maxBodyHeight(visibleHeight: 10, chrome: 50) == 40)
    }
}

@Suite struct HotKeyTests {
    /// ⌘⌥Space, the combination macOS ships for "Show Finder search window" (ID 65).
    private let commandOptionSpace = HotKeySpec(
        keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | optionKey),
        cocoaModifiers: 1_572_864, label: "⌘⌥Space"
    )

    @Test func bindingsMatchSpec() {
        #expect(HotKeySpec.trigger.keyCode == UInt32(kVK_ANSI_I))
        #expect(HotKeySpec.trigger.carbonModifiers == UInt32(controlKey))
        // NSEvent.ModifierFlags.control, as stored by System Settings.
        #expect(HotKeySpec.trigger.cocoaModifiers == 262_144)
        #expect(HotKeySpec.trigger.label == "⌃I")
        // Turkish-Q (PC) layout: the "I/ı" key is ANSI I (34), the "İ/i" key is ANSI ' (39),
        // and "," sits on the ANSI \ key (42). ANSI comma (43) types "ö" there.
        #expect(HotKeySpec.triggerAlternate.keyCode == 39)
        #expect(HotKeySpec.triggerAlternate.carbonModifiers == UInt32(controlKey))
        #expect(HotKeySpec.triggerAlternate.cocoaModifiers == 262_144)
        #expect(HotKeySpec.triggerAlternate.label == "⌃İ")
        #expect(HotKeySpec.fontLarger.keyCode == UInt32(kVK_UpArrow))
        #expect(HotKeySpec.fontSmaller.keyCode == UInt32(kVK_DownArrow))
        #expect(HotKeySpec.fontReset.keyCode == UInt32(kVK_LeftArrow))
        for spec in [HotKeySpec.fontLarger, .fontSmaller, .fontReset] {
            #expect(spec.carbonModifiers == UInt32(controlKey | optionKey))
            #expect(spec.cocoaModifiers == 786_432)
        }
        #expect(HotKeySpec.fontLarger.label == "⌃⌥↑")
        #expect(HotKeySpec.fontSmaller.label == "⌃⌥↓")
        #expect(HotKeySpec.fontReset.label == "⌃⌥←")
        #expect(HotKeySpec.quit.keyCode == UInt32(kVK_ANSI_K))
        #expect(HotKeySpec.quit.carbonModifiers == UInt32(controlKey | optionKey))
        #expect(HotKeySpec.quit.cocoaModifiers == 786_432)
        #expect(HotKeySpec.quit.label == "⌃⌥K")
        #expect(HotKeySpec.all == [.trigger, .triggerAlternate, .toggle, .fontLarger, .fontSmaller, .fontReset, .quit])
        #expect(HotKeySpec.toggle.keyCode == 42)
        #expect(HotKeySpec.toggle.carbonModifiers == UInt32(controlKey))
        #expect(HotKeySpec.toggle.cocoaModifiers == 262_144)
        #expect(HotKeySpec.toggle.label == "⌃,")
    }

    @Test func userFacingTextNamesTheCurrentShortcuts() {
        #expect(UIText.ready.contains("⌃I"))
        #expect(UIText.noResponseYet.contains("⌃I"))
        #expect(UIText.menuTrigger.contains("⌃I"))
        #expect(UIText.footerNotice.contains("⌃,"))
        #expect(!UIText.ready.contains("⌃⌥⌘Space"))
        #expect(!UIText.footerNotice.contains("⌘⌥H"))
    }

    @Test func ourShortcutsAreFreeOnUntouchedPreferences() {
        #expect(SymbolicHotKeys.conflicts(for: .trigger, in: nil).isEmpty)
        #expect(SymbolicHotKeys.conflicts(for: .toggle, in: nil).isEmpty)
    }

    private func controlArrow(_ keyCode: Int) -> HotKeySpec {
        HotKeySpec(keyCode: UInt32(keyCode), carbonModifiers: UInt32(controlKey), cocoaModifiers: 262_144, label: "⌃arrow")
    }

    /// Plain ⌃ arrows belong to Mission Control and Spaces out of the box; ⌃⌥ arrows do not.
    @Test func fontKeysAvoidMissionControlAndSpaces() {
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_UpArrow), in: nil) == ["32"])
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_DownArrow), in: nil) == ["33"])
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_LeftArrow), in: nil) == ["79"])
        // The user's own preferences hold bare {"enabled": true} entries for 79-82.
        let userTable: [String: Any] = ["79": ["enabled": true], "80": ["enabled": true],
                                        "81": ["enabled": true], "82": ["enabled": true]]
        for spec in [HotKeySpec.fontLarger, .fontSmaller, .fontReset, .quit] {
            #expect(SymbolicHotKeys.conflicts(for: spec, in: nil).isEmpty)
            #expect(SymbolicHotKeys.conflicts(for: spec, in: userTable).isEmpty)
        }
    }

    @Test func enabledEntryWithoutBindingUsesTheShippedKeys() {
        let table: [String: Any] = ["79": ["enabled": true]]
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_LeftArrow), in: table) == ["79"])
    }

    @Test func disabledArrowShortcutsFreeTheKeys() {
        let table: [String: Any] = [
            "32": ["enabled": false, "value": ["parameters": [65_535, 126, 8_650_752], "type": "standard"]],
            "33": ["enabled": 0],
            "79": ["enabled": false],
        ]
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_UpArrow), in: table).isEmpty)
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_DownArrow), in: table).isEmpty)
        #expect(SymbolicHotKeys.conflicts(for: controlArrow(kVK_LeftArrow), in: table).isEmpty)
    }

    @Test func customArrowBindingWithFunctionFlagClashes() {
        let table: [String: Any] = [
            "200": ["enabled": true, "value": ["parameters": [65_535, 126, 9_175_040]]],
        ]
        #expect(SymbolicHotKeys.conflicts(for: .fontLarger, in: table) == ["200"])
    }

    @Test func shippedDefaultsCountAsEnabledWhenAbsent() {
        #expect(SymbolicHotKeys.conflicts(for: commandOptionSpace, in: nil) == ["65"])
    }

    @Test func disabledSystemShortcutDoesNotClash() {
        let table: [String: Any] = ["65": ["enabled": false, "value": ["parameters": [32, 49, 1_572_864], "type": "standard"]]]
        #expect(SymbolicHotKeys.conflicts(for: commandOptionSpace, in: table).isEmpty)
    }

    @Test func remappedSystemShortcutDoesNotClash() {
        let table: [String: Any] = ["65": ["enabled": 1, "value": ["parameters": [102, 3, 1_572_864], "type": "standard"]]]
        #expect(SymbolicHotKeys.conflicts(for: commandOptionSpace, in: table).isEmpty)
    }

    @Test func anyEnabledShortcutOnTheSameKeysClashes() {
        let table: [String: Any] = [
            "65": ["enabled": 0, "value": ["parameters": [32, 49, 1_572_864]]],
            "200": ["enabled": true, "value": ["parameters": [44, 42, 262_144]]],
            "201": ["enabled": 1, "value": ["parameters": [105, 34, 262_144]]],
        ]
        #expect(SymbolicHotKeys.conflicts(for: .toggle, in: table) == ["200"])
        #expect(SymbolicHotKeys.conflicts(for: .trigger, in: table) == ["201"])
        let alternate: [String: Any] = ["202": ["enabled": true, "value": ["parameters": [105, 39, 262_144]]]]
        #expect(SymbolicHotKeys.conflicts(for: .triggerAlternate, in: alternate) == ["202"])
        #expect(SymbolicHotKeys.conflicts(for: .trigger, in: alternate).isEmpty)
    }

    @Test func modifiersMustMatchExactly() {
        // ⌃⌥I must not count as ⌃I.
        let table: [String: Any] = ["61": ["enabled": true, "value": ["parameters": [105, 34, 786_432]]]]
        #expect(SymbolicHotKeys.conflicts(for: .trigger, in: table).isEmpty)
    }
}
