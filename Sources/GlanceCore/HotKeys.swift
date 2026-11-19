import Carbon.HIToolbox
import CoreFoundation

public struct HotKeySpec: Equatable, Sendable {
    public let keyCode: UInt32
    /// Carbon modifier mask for `RegisterEventHotKey`.
    public let carbonModifiers: UInt32
    /// `NSEvent.ModifierFlags` raw value, the form `com.apple.symbolichotkeys` stores.
    public let cocoaModifiers: Int
    public let label: String

    static let commandFlag = 1 << 20
    static let optionFlag = 1 << 19
    static let controlFlag = 1 << 18

    // Key codes are physical positions, so they are chosen for the Turkish-Q (PC) layout.

    /// ⌃I: capture the screen and ask. This is the "I/ı" key (ANSI I).
    public static let trigger = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_I),
        carbonModifiers: UInt32(controlKey),
        cocoaModifiers: controlFlag,
        label: "⌃I"
    )

    /// ⌃İ: the same action on the "İ/i" key (ANSI ').
    public static let triggerAlternate = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_Quote),
        carbonModifiers: UInt32(controlKey),
        cocoaModifiers: controlFlag,
        label: "⌃İ"
    )

    /// ⌃,: show or hide the HUD without a new request. On Turkish-Q "," is the ANSI \ key;
    /// ANSI comma types "ö".
    public static let toggle = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_Backslash),
        carbonModifiers: UInt32(controlKey),
        cocoaModifiers: controlFlag,
        label: "⌃,"
    )

    /// ⌃⌥↑ / ⌃⌥↓: answer text half a point larger / smaller; ⌃⌥←: back to `AppConfig.baseFontSize`.
    /// Option is needed because macOS keeps plain ⌃ arrows for Mission Control and Spaces.
    public static let fontLarger = HotKeySpec(
        keyCode: UInt32(kVK_UpArrow), carbonModifiers: UInt32(controlKey | optionKey),
        cocoaModifiers: controlFlag | optionFlag, label: "⌃⌥↑"
    )

    public static let fontSmaller = HotKeySpec(
        keyCode: UInt32(kVK_DownArrow), carbonModifiers: UInt32(controlKey | optionKey),
        cocoaModifiers: controlFlag | optionFlag, label: "⌃⌥↓"
    )

    public static let fontReset = HotKeySpec(
        keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(controlKey | optionKey),
        cocoaModifiers: controlFlag | optionFlag, label: "⌃⌥←"
    )

    /// ⌃⌥K: quit the app.
    public static let quit = HotKeySpec(
        keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | optionKey),
        cocoaModifiers: controlFlag | optionFlag, label: "⌃⌥K"
    )

    public static let all: [HotKeySpec] = [
        .trigger, .triggerAlternate, .toggle, .fontLarger, .fontSmaller, .fontReset, .quit,
    ]
}

/// System shortcuts (System Settings > Keyboard > Keyboard Shortcuts) win over `RegisterEventHotKey`,
/// so a clash means our hotkey silently never fires.
public enum SymbolicHotKeys {
    public static let finderSearchID = "65"

    /// Shortcuts macOS enables out of the box; they are missing from the preferences until the user edits them.
    static let shippedDefaults: [String: (keyCode: Int, modifiers: Int)] = [
        "64": (kVK_Space, HotKeySpec.commandFlag),                            // Spotlight
        finderSearchID: (kVK_Space, HotKeySpec.commandFlag | HotKeySpec.optionFlag), // Finder search window
        "32": (kVK_UpArrow, HotKeySpec.controlFlag),                          // Mission Control
        "33": (kVK_DownArrow, HotKeySpec.controlFlag),                        // Application windows
        "79": (kVK_LeftArrow, HotKeySpec.controlFlag),                        // Move left a space
        "81": (kVK_RightArrow, HotKeySpec.controlFlag),                       // Move right a space
    ]

    /// Flags macOS adds to arrow and function keys (`.function`, `.numericPad`); they say nothing about
    /// which modifiers the user holds, so they are ignored when comparing.
    static let keyKindFlags = (1 << 23) | (1 << 21)

    /// IDs of enabled system shortcuts bound to the same keys as `spec`.
    /// `table` is the `AppleSymbolicHotKeys` dictionary from the `com.apple.symbolichotkeys` domain.
    public static func conflicts(for spec: HotKeySpec, in table: [String: Any]?) -> [String] {
        let table = table ?? [:]
        var ids: [String] = []
        for (id, value) in table {
            guard let entry = value as? [String: Any], isEnabled(entry),
                  let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
                  parameters.count >= 3
            else { continue }
            if parameters[1] == Int(spec.keyCode), parameters[2] & ~keyKindFlags == spec.cocoaModifiers {
                ids.append(id)
            }
        }
        for (id, binding) in shippedDefaults where usesShippedBinding(table[id]) {
            if binding.keyCode == Int(spec.keyCode), binding.modifiers == spec.cocoaModifiers {
                ids.append(id)
            }
        }
        return ids.sorted()
    }

    public static func readTable() -> [String: Any]? {
        CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
            as? [String: Any]
    }

    /// True when the shortcut is on with macOS's own keys: never edited, or switched on without a custom binding.
    private static func usesShippedBinding(_ value: Any?) -> Bool {
        guard let value else { return true }
        guard let entry = value as? [String: Any], isEnabled(entry) else { return false }
        return entry["value"] == nil
    }

    private static func isEnabled(_ entry: [String: Any]) -> Bool {
        if let flag = entry["enabled"] as? Bool { return flag }
        if let number = entry["enabled"] as? Int { return number != 0 }
        return true
    }
}
