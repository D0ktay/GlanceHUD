import Foundation
import Security

/// Finds the Anthropic API key: environment first (handy for terminal runs), then the Keychain, then the config file.
public enum APIKeySource {
    public static let environmentVariable = "ANTHROPIC_API_KEY"
    public static let keychainService = "GlanceHUD"
    public static let keychainAccount = "anthropic-api-key"

    public static func resolve(
        environment: [String: String],
        keychain: () -> String?,
        config: AppConfig
    ) -> String? {
        if let key = environment[environmentVariable]?.trimmed, !key.isEmpty { return key }
        if let key = keychain()?.trimmed, !key.isEmpty { return key }
        if let key = config.apiKey?.trimmed, !key.isEmpty { return key }
        return nil
    }

    /// Generic-password item added with
    /// `security add-generic-password -s GlanceHUD -a anthropic-api-key -w`.
    public static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
