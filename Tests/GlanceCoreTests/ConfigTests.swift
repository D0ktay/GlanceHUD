import Foundation
import Testing
@testable import GlanceCore

@Suite struct AppConfigTests {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    @Test func emptyObjectGivesDefaults() throws {
        #expect(try decode("{}") == .default)
    }

    @Test func defaultsMatchSpec() {
        let config = AppConfig.default
        #expect(config.model == "claude-opus-5-5")
        #expect(config.autoShow == false)
        #expect(config.autoHideSeconds == 10)
        #expect(config.fontSize == 11)
        #expect(config.textGray == 0.5)
        #expect(config.textOpacity == 0.7)
        #expect(config.showBox == false)
        #expect(config.apiKey == nil)
    }

    @Test func textToneIsClampedSoItNeverVanishes() throws {
        let config = try decode(#"{"textGray": 3, "textOpacity": 0}"#)
        #expect(config.textGray == 1)
        #expect(config.textOpacity == 0.15)
        #expect(try decode(#"{"textGray": 0.3, "textOpacity": 0.5}"#).textOpacity == 0.5)
    }

    @Test func boxCanBeTurnedBackOn() throws {
        #expect(try decode(#"{"showBox": true}"#).showBox)
        #expect(try decode(#"{"showBox": "yes"}"#).showBox == false)
    }

    @Test func autoShowIsOptIn() throws {
        #expect(try decode(#"{"autoShow": true}"#).autoShow)
        #expect(try decode("{}").autoShow == false)
    }

    @Test func partialFileOverridesOnlyGivenFields() throws {
        let config = try decode(#"{"model": "claude-sonnet-5-5", "autoHideSeconds": 0, "apiKey": "sk-test"}"#)
        #expect(config.model == "claude-sonnet-5-5")
        #expect(config.autoHideSeconds == 0)
        #expect(config.apiKey == "sk-test")
        #expect(config.prompt == AppConfig.defaultPrompt)
        #expect(config.maxTokens == AppConfig.default.maxTokens)
    }

    @Test func mistypedFieldFallsBackToDefault() throws {
        let config = try decode(#"{"maxTokens": "lots", "fontSize": 15}"#)
        #expect(config.maxTokens == AppConfig.default.maxTokens)
        #expect(config.fontSize == 15)
    }

    @Test func outOfRangeValuesAreClamped() throws {
        let config = try decode(#"{"maxTokens": 10, "autoHideSeconds": -5, "maxImageLongEdge": 100000, "jpegQuality": 7, "hudWidth": 50, "fontSize": 200}"#)
        #expect(config.maxTokens == 1_024)
        #expect(config.autoHideSeconds == 0)
        #expect(config.maxImageLongEdge == 8_000)
        #expect(config.jpegQuality == 1)
        #expect(config.hudWidth == 240)
        #expect(config.fontSize == 32)
    }

    @Test func blankAndUnknownStringsRestoreDefaults() throws {
        let config = try decode(#"{"model": "  ", "prompt": "", "effort": "hight"}"#)
        #expect(config.model == AppConfig.default.model)
        #expect(config.prompt == AppConfig.defaultPrompt)
        #expect(config.effort == AppConfig.default.effort)
    }

    @Test func effortIsNormalisedAndMayBeEmpty() throws {
        #expect(try decode(#"{"effort": " HIGH "}"#).effort == "high")
        #expect(try decode(#"{"effort": ""}"#).effort == "")
    }
}

@Suite struct ConfigStoreTests {
    private func temporaryStore() -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceHUDTests-\(UUID().uuidString)", isDirectory: true)
        return ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    }

    @Test func missingFileLoadsDefaultsWithoutWarning() {
        let result = temporaryStore().load()
        #expect(result.config == .default)
        #expect(result.warning == nil)
    }

    @Test func writesDefaultsOnceWithPrivatePermissions() throws {
        let store = temporaryStore()
        #expect(try store.writeDefaultIfMissing())
        #expect(store.load().config == .default)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.contains("apiKey"))
        #expect(text.contains("Bu ekran görüntüsüne bak"))
    }

    @Test func neverOverwritesAnExistingFile() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model": "mine"}"#.utf8).write(to: store.fileURL)
        #expect(try store.writeDefaultIfMissing() == false)
        #expect(store.load().config.model == "mine")
    }

    @Test func brokenFileFallsBackWithWarning() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        let result = store.load()
        #expect(result.config == .default)
        #expect(result.warning?.contains(store.fileURL.path) == true)
    }
}

@Suite struct APIKeySourceTests {
    private func config(apiKey: String?) -> AppConfig {
        var config = AppConfig.default
        config.apiKey = apiKey
        return config
    }

    @Test func environmentWinsOverKeychainAndFile() {
        let key = APIKeySource.resolve(environment: ["ANTHROPIC_API_KEY": " env-key\n"], keychain: { "kc-key" },
                                       config: config(apiKey: "file-key"))
        #expect(key == "env-key")
    }

    @Test func keychainWinsOverFile() {
        let key = APIKeySource.resolve(environment: [:], keychain: { "kc-key" }, config: config(apiKey: "file-key"))
        #expect(key == "kc-key")
    }

    @Test func blankSourcesAreSkipped() {
        let key = APIKeySource.resolve(environment: ["ANTHROPIC_API_KEY": "  "], keychain: { "" },
                                       config: config(apiKey: "file-key"))
        #expect(key == "file-key")
    }

    @Test func noKeyAnywhereGivesNil() {
        #expect(APIKeySource.resolve(environment: [:], keychain: { nil }, config: config(apiKey: nil)) == nil)
    }
}

@Suite struct FontSizeStepTests {
    private func temporaryStore() -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceHUDTests-\(UUID().uuidString)", isDirectory: true)
        return ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    }

    @Test func resetSizeIsNinePoints() {
        #expect(AppConfig.baseFontSize == 9)
    }

    @Test func stepsByHalfAPoint() {
        #expect(AppConfig.fontSizeStep == 0.5)
        #expect(AppConfig.steppedFontSize(9, by: 1) == 9.5)
        #expect(AppConfig.steppedFontSize(9, by: -1) == 8.5)
    }

    @Test func snapsOddSizesToTheHalfPointGrid() {
        #expect(AppConfig.steppedFontSize(9.3, by: 1) == 9.5)
        #expect(AppConfig.steppedFontSize(9.3, by: -1) == 9)
    }

    @Test func staysInsideTheAllowedRange() {
        #expect(AppConfig.fontSizeRange == 6...32)
        #expect(AppConfig.steppedFontSize(6, by: -1) == 6)
        #expect(AppConfig.steppedFontSize(32, by: 1) == 32)
    }

    @Test func smallSizesSurviveLoading() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"fontSize": 7.5}"#.utf8))
        #expect(config.fontSize == 7.5)
        let tiny = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"fontSize": 2}"#.utf8))
        #expect(tiny.fontSize == 6)
    }

    @Test func writingFontSizeKeepsEveryOtherKey() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model": "mine", "fontSize": 9, "unknownKey": 1, "apiKey": "secret"}"#.utf8).write(to: store.fileURL)
        try store.writeFontSize(9.5)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        #expect(object?["fontSize"] as? Double == 9.5)
        #expect(object?["model"] as? String == "mine")
        #expect(object?["unknownKey"] as? Int == 1)
        #expect(object?["apiKey"] as? String == "secret")
        #expect(store.load().config.fontSize == 9.5)
    }

    @Test func writingFontSizeLeavesABrokenFileAlone() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.writeFontSize(10) }
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == "{not json")
    }
}
