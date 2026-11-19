import Foundation

/// The parts of the Messages API event stream the HUD cares about. Thinking blocks and pings are dropped.
public enum StreamEvent: Equatable, Sendable {
    case messageStart(model: String?)
    case textDelta(String)
    /// A server-side fallback took over after a safety decline. Already-received text stays valid:
    /// the fallback model continues from it.
    case fallback(fromModel: String?, toModel: String?)
    case messageDelta(stopReason: String?, refusalCategory: String?)
    case messageStop
    case error(type: String, message: String)
}

public enum SSEParser {
    /// Parses one line of the event stream. Each Anthropic event carries its whole JSON payload on a single
    /// `data:` line (the `event:` line repeats the JSON `type`), so every other line returns nil.
    public static func event(fromLine line: some StringProtocol) -> StreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).drop(while: { $0 == " " })
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let raw = try? decoder.decode(RawEvent.self, from: Data(payload.utf8)) else { return nil }

        switch raw.type {
        case "message_start":
            return .messageStart(model: raw.message?.model)
        case "content_block_start":
            switch raw.contentBlock?.type {
            case "fallback":
                return .fallback(fromModel: raw.contentBlock?.from?.model, toModel: raw.contentBlock?.to?.model)
            case "text":
                guard let text = raw.contentBlock?.text, !text.isEmpty else { return nil }
                return .textDelta(text)
            default:
                return nil
            }
        case "content_block_delta":
            guard raw.delta?.type == "text_delta", let text = raw.delta?.text else { return nil }
            return .textDelta(text)
        case "message_delta":
            let category = raw.delta?.stopDetails?.category ?? raw.stopDetails?.category
            return .messageDelta(stopReason: raw.delta?.stopReason, refusalCategory: category)
        case "message_stop":
            return .messageStop
        case "error":
            return .error(type: raw.error?.type ?? "unknown_error", message: raw.error?.message ?? "")
        default:
            return nil
        }
    }

    private struct RawEvent: Decodable {
        struct Message: Decodable { let model: String? }
        struct ModelRef: Decodable { let model: String? }
        struct Block: Decodable {
            let type: String?
            let text: String?
            let from: ModelRef?
            let to: ModelRef?
        }
        struct StopDetails: Decodable { let category: String? }
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?
            let stopDetails: StopDetails?
        }
        struct ErrorBody: Decodable {
            let type: String?
            let message: String?
        }

        let type: String
        let message: Message?
        let contentBlock: Block?
        let delta: Delta?
        let stopDetails: StopDetails?
        let error: ErrorBody?
    }
}
