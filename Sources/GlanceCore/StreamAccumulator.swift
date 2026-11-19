import Foundation

public enum StreamOutcome: Equatable, Sendable {
    case completed(text: String, truncated: Bool)
    /// The safety classifiers declined (after any server-side fallback). Partial text must not be shown.
    case refused(category: String?)
    case failed(GlanceError, partialText: String)
    /// The connection ended without `message_stop`.
    case incomplete(partialText: String)
}

/// Folds stream events into the text shown so far and, at the end, an outcome.
public struct StreamAccumulator: Sendable {
    public private(set) var text = ""
    public private(set) var model: String?
    private var stopReason: String?
    private var refusalCategory: String?
    private var streamError: GlanceError?
    private var sawMessageStop = false

    public init() {}

    public mutating func apply(_ event: StreamEvent) {
        switch event {
        case .messageStart(let model):
            if let model { self.model = model }
        case .textDelta(let delta):
            text += delta
        case .fallback(_, let toModel):
            if let toModel { model = toModel }
        case .messageDelta(let reason, let category):
            if let reason { stopReason = reason }
            if let category { refusalCategory = category }
        case .messageStop:
            sawMessageStop = true
        case .error(let type, let message):
            streamError = .stream(type: type, message: message)
        }
    }

    public var outcome: StreamOutcome {
        if let streamError { return .failed(streamError, partialText: text) }
        if stopReason == "refusal" { return .refused(category: refusalCategory) }
        guard sawMessageStop else { return .incomplete(partialText: text) }
        return .completed(text: text.trimmed, truncated: stopReason == "max_tokens")
    }
}
