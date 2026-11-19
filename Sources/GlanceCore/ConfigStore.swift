import Foundation

/// Reads and seeds `~/Library/Application Support/GlanceHUD/config.json`.
public struct ConfigStore: Sendable {
    public struct LoadResult: Sendable {
        public let config: AppConfig
        /// Set when the file exists but could not be used; the defaults are returned instead.
        public let warning: String?
    }

    public let fileURL: URL

    public init(fileURL: URL = ConfigStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlanceHUD", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(config: .default, warning: nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return LoadResult(config: try JSONDecoder().decode(AppConfig.self, from: data), warning: nil)
        } catch {
            return LoadResult(config: .default, warning: UIText.configUnreadable(path: fileURL.path))
        }
    }

    /// Writes the default settings so the user has a file to edit. Never overwrites an existing file.
    @discardableResult
    public func writeDefaultIfMissing() throws -> Bool {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: fileURL.path) else { return false }
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(AppConfig.default).write(to: fileURL, options: .atomic)
        // The file may later hold an API key.
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return true
    }

    /// Writes only the capture region, leaving every other key in the file (even unknown ones) untouched.
    /// nil removes it, so capture returns to the whole screen.
    public func writeCaptureRect(_ rect: CaptureRect?) throws {
        try updateKeys { object in
            if let rect {
                object["captureRect"] = ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
            } else {
                object.removeValue(forKey: "captureRect")
            }
        }
    }

    /// Writes only the font size, leaving every other key in the file untouched.
    public func writeFontSize(_ size: Double) throws {
        try updateKeys { $0["fontSize"] = size }
    }

    private func updateKeys(_ change: (inout [String: Any]) -> Void) throws {
        try writeDefaultIfMissing()
        // Never start from an empty dict on a parse failure: that would wipe every other key
        // (a file-stored apiKey included). Bail out and leave the file as it is.
        let existing = try Data(contentsOf: fileURL)
        guard var object = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        change(&object)
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
