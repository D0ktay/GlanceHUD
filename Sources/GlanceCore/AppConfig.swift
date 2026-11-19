import Foundation

/// User-editable settings, stored as JSON in Application Support.
/// Every field is optional in the file; missing, mistyped or out-of-range values fall back to defaults.
public struct AppConfig: Codable, Equatable, Sendable {
    public var model: String
    /// `output_config.effort`; an empty string leaves it out of the request.
    public var effort: String
    public var maxTokens: Int
    public var prompt: String
    /// Show answers (and errors) by themselves as they arrive. Off by default: they wait for ⌃,.
    public var autoShow: Bool
    /// With `autoShow`, seconds after a finished answer before it hides itself; 0 turns auto-hide off.
    public var autoHideSeconds: Double
    public var maxImageLongEdge: Int
    public var jpegQuality: Double
    /// Widest the text may run before it wraps (points).
    public var hudWidth: Double
    public var fontSize: Double
    /// Without the box: gray level of the text, 0 = black … 1 = white.
    public var textGray: Double
    /// Without the box: opacity of the text, low enough that it does not draw the eye.
    public var textOpacity: Double
    /// Draw the dark rounded box and footer line; off by default, showing only the answer text.
    public var showBox: Bool
    public var showMenuBarIcon: Bool
    /// Capture only this sub-region of the main display instead of the whole screen; nil = whole screen.
    /// Set by the calibration overlay, not meant to be hand-edited.
    public var captureRect: CaptureRect?
    /// Last-resort key source; the environment and the Keychain are checked first.
    public var apiKey: String?

    public static let defaultPrompt =
        "Bu ekran görüntüsüne bak. Ekranda üzerinde çalıştığım asıl soruyu ya da işi bul ve en yararlı yanıtı kısa ve net ver."

    public static let fontSizeRange: ClosedRange<Double> = 6...32
    /// The size ⌃⌥← returns to: the user's own setting, not the 11 pt default for new installs.
    public static let baseFontSize = 9.0
    /// How much one press of the font-size hotkeys changes the size (points).
    public static let fontSizeStep = 0.5

    /// `current` moved `steps` notches along the half-point grid, kept inside `fontSizeRange`.
    /// An off-grid size first snaps to the nearest notch in the direction of travel.
    public static func steppedFontSize(_ current: Double, by steps: Int) -> Double {
        let notch = current / fontSizeStep
        let base = steps > 0 ? (notch + 1e-9).rounded(.down) : (notch - 1e-9).rounded(.up)
        return ((base + Double(steps)) * fontSizeStep).clamped(fontSizeRange)
    }

    public static let allowedEfforts: Set<String> = ["low", "medium", "high", "xhigh", "max"]

    public static let `default` = AppConfig(
        model: "claude-opus-5-5",
        effort: "low",
        maxTokens: 16_000,
        prompt: defaultPrompt,
        autoShow: false,
        autoHideSeconds: 10,
        maxImageLongEdge: 2048,
        jpegQuality: 0.85,
        hudWidth: 480,
        fontSize: 11,
        textGray: 0.5,
        textOpacity: 0.7,
        showBox: false,
        showMenuBarIcon: true,
        captureRect: nil,
        apiKey: nil
    )

    public init(
        model: String, effort: String, maxTokens: Int, prompt: String, autoShow: Bool, autoHideSeconds: Double,
        maxImageLongEdge: Int, jpegQuality: Double, hudWidth: Double, fontSize: Double,
        textGray: Double, textOpacity: Double, showBox: Bool, showMenuBarIcon: Bool,
        captureRect: CaptureRect?, apiKey: String?
    ) {
        self.model = model
        self.effort = effort
        self.maxTokens = maxTokens
        self.prompt = prompt
        self.autoShow = autoShow
        self.autoHideSeconds = autoHideSeconds
        self.maxImageLongEdge = maxImageLongEdge
        self.jpegQuality = jpegQuality
        self.hudWidth = hudWidth
        self.fontSize = fontSize
        self.textGray = textGray
        self.textOpacity = textOpacity
        self.showBox = showBox
        self.showMenuBarIcon = showMenuBarIcon
        self.captureRect = captureRect
        self.apiKey = apiKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppConfig.default
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
        }
        model = value(.model, fallback.model)
        effort = value(.effort, fallback.effort)
        maxTokens = value(.maxTokens, fallback.maxTokens)
        prompt = value(.prompt, fallback.prompt)
        autoShow = value(.autoShow, fallback.autoShow)
        autoHideSeconds = value(.autoHideSeconds, fallback.autoHideSeconds)
        maxImageLongEdge = value(.maxImageLongEdge, fallback.maxImageLongEdge)
        jpegQuality = value(.jpegQuality, fallback.jpegQuality)
        hudWidth = value(.hudWidth, fallback.hudWidth)
        fontSize = value(.fontSize, fallback.fontSize)
        textGray = value(.textGray, fallback.textGray)
        textOpacity = value(.textOpacity, fallback.textOpacity)
        showBox = value(.showBox, fallback.showBox)
        showMenuBarIcon = value(.showMenuBarIcon, fallback.showMenuBarIcon)
        captureRect = try? container.decodeIfPresent(CaptureRect.self, forKey: .captureRect)
        apiKey = try? container.decodeIfPresent(String.self, forKey: .apiKey)
        self = sanitized()
    }

    /// Clamps numbers into safe ranges and restores defaults for blank or unknown strings.
    public func sanitized() -> AppConfig {
        let fallback = AppConfig.default
        var copy = self
        copy.model = model.trimmed.isEmpty ? fallback.model : model.trimmed
        let effortValue = effort.trimmed.lowercased()
        copy.effort = effortValue.isEmpty || Self.allowedEfforts.contains(effortValue) ? effortValue : fallback.effort
        copy.prompt = prompt.trimmed.isEmpty ? fallback.prompt : prompt
        copy.maxTokens = maxTokens.clamped(1_024...128_000)
        copy.autoHideSeconds = autoHideSeconds.isFinite ? autoHideSeconds.clamped(0...3_600) : fallback.autoHideSeconds
        copy.maxImageLongEdge = maxImageLongEdge.clamped(256...8_000)
        copy.jpegQuality = jpegQuality.isFinite ? jpegQuality.clamped(0.3...1) : fallback.jpegQuality
        copy.hudWidth = hudWidth.isFinite ? hudWidth.clamped(240...1_600) : fallback.hudWidth
        copy.fontSize = fontSize.isFinite ? fontSize.clamped(Self.fontSizeRange) : fallback.fontSize
        copy.textGray = textGray.isFinite ? textGray.clamped(0...1) : fallback.textGray
        // Below ~0.15 the answer would be practically invisible.
        copy.textOpacity = textOpacity.isFinite ? textOpacity.clamped(0.15...1) : fallback.textOpacity
        if let rect = captureRect,
           !(rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
             && rect.width > 0 && rect.height > 0) {
            copy.captureRect = nil
        }
        return copy
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Comparable {
    func clamped(_ range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
