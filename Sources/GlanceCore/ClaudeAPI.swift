import Foundation

/// Wire-level details of the Claude Messages API call. Swift has no official Anthropic SDK, so this is raw HTTP.
public enum ClaudeAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    /// Gates `fallbacks: "default"`: after a safety-classifier decline the API retries on a recommended model
    /// inside the same call instead of returning the refusal.
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public static let systemPrompt = """
        You are a screen assistant. The user pressed a hotkey to send you a screenshot of their main display, \
        and your reply is shown in a small floating overlay in a monospace font that cannot be scrolled. \
        Work out what on the screen they most likely want help with and answer it directly. \
        Write plain text only: no Markdown headings, bold, tables or code fences; use simple "-" lists, \
        and put code on plain lines. Keep it short, usually under 120 words, unless the task needs more \
        (for example code). Reply in the same language as the user's instruction.
        """

    /// Models that accept `fallbacks: "default"`; other models would reject the parameter.
    static let fallbackModelPrefixes = ["claude-opus-5", "claude-fable-5", "claude-mythos-5", "claude-sonnet-5-5"]

    public static func supportsServerFallback(model: String) -> Bool {
        fallbackModelPrefixes.contains { model.hasPrefix($0) }
    }

    public static func makeRequest(imageJPEG: Data, config: AppConfig, apiKey: String) throws -> URLRequest {
        let fallback = supportsServerFallback(model: config.model)
        let body = MessagesBody(
            model: config.model,
            maxTokens: config.maxTokens,
            stream: true,
            system: systemPrompt,
            outputConfig: config.effort.isEmpty ? nil : .init(effort: config.effort),
            fallbacks: fallback ? "default" : nil,
            messages: [
                .init(role: "user", content: [
                    .init(type: "image", source: .init(type: "base64", mediaType: "image/jpeg",
                                                       data: imageJPEG.base64EncodedString())),
                    .init(type: "text", text: config.prompt),
                ]),
            ]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        if fallback {
            request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try encoder.encode(body)
        return request
    }
}

/// Request body; keys are converted to snake_case when encoded, and nil fields are left out.
struct MessagesBody: Encodable {
    struct OutputConfig: Encodable {
        let effort: String
    }

    struct ImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String
    }

    struct ContentBlock: Encodable {
        let type: String
        var text: String? = nil
        var source: ImageSource? = nil
    }

    struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    let model: String
    let maxTokens: Int
    let stream: Bool
    let system: String
    let outputConfig: OutputConfig?
    let fallbacks: String?
    let messages: [Message]
}
