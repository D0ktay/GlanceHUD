import Foundation
import Testing
@testable import GlanceCore

@Suite struct RequestTests {
    private let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func targetsMessagesEndpointWithRequiredHeaders() throws {
        let request = try ClaudeAPI.makeRequest(imageJPEG: image, config: .default, apiKey: "sk-test")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
    }

    @Test func bodyStreamsWithEffortAndDefaultFallback() throws {
        let json = try body(of: try ClaudeAPI.makeRequest(imageJPEG: image, config: .default, apiKey: "k"))
        #expect(json["model"] as? String == "claude-opus-5-5")
        #expect(json["max_tokens"] as? Int == 16_000)
        #expect(json["stream"] as? Bool == true)
        #expect(json["fallbacks"] as? String == "default")
        #expect((json["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(json["system"] as? String == ClaudeAPI.systemPrompt)
        // Thinking stays at the model default (adaptive); disabling it is a 400 on Opus 5.5.
        #expect(json["thinking"] == nil)
        #expect(json["temperature"] == nil)
    }

    @Test func imageComesBeforeThePromptAsBase64JPEG() throws {
        let json = try body(of: try ClaudeAPI.makeRequest(imageJPEG: image, config: .default, apiKey: "k"))
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "image")
        let source = try #require(content[0]["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/jpeg")
        let encoded = try #require(source["data"] as? String)
        #expect(Data(base64Encoded: encoded) == image)
        #expect(!encoded.contains("\n"))
        #expect(content[1]["type"] as? String == "text")
        #expect(content[1]["text"] as? String == AppConfig.defaultPrompt)
        #expect(content[0]["text"] == nil)
    }

    @Test func fallbackIsOmittedForModelsWithoutIt() throws {
        var config = AppConfig.default
        config.model = "claude-haiku-4-5"
        let request = try ClaudeAPI.makeRequest(imageJPEG: image, config: config, apiKey: "k")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(try body(of: request)["fallbacks"] == nil)
    }

    @Test func emptyEffortOmitsOutputConfig() throws {
        var config = AppConfig.default
        config.effort = ""
        #expect(try body(of: try ClaudeAPI.makeRequest(imageJPEG: image, config: config, apiKey: "k"))["output_config"] == nil)
    }

    @Test func fallbackSupportByModel() {
        #expect(ClaudeAPI.supportsServerFallback(model: "claude-opus-5-5"))
        #expect(ClaudeAPI.supportsServerFallback(model: "claude-opus-5"))
        #expect(ClaudeAPI.supportsServerFallback(model: "claude-fable-5-1"))
        #expect(ClaudeAPI.supportsServerFallback(model: "claude-sonnet-5-5"))
        #expect(!ClaudeAPI.supportsServerFallback(model: "claude-haiku-5-5"))
        #expect(!ClaudeAPI.supportsServerFallback(model: "claude-sonnet-4-6"))
    }
}
