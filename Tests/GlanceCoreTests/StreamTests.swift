import Foundation
import Testing
@testable import GlanceCore

@Suite struct SSEParserTests {
    @Test func messageStartCarriesModel() {
        let line = #"data: {"type":"message_start","message":{"id":"msg_1","type":"message","model":"claude-opus-5-5","content":[]}}"#
        #expect(SSEParser.event(fromLine: line) == .messageStart(model: "claude-opus-5-5"))
    }

    @Test func textDeltaWithAndWithoutSpaceAfterColon() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Merhaba"}}"#)
            == .textDelta("Merhaba"))
        #expect(SSEParser.event(fromLine: #"data:{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}}"#)
            == .textDelta("x"))
    }

    @Test func thinkingAndSignatureDeltasAreIgnored() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#) == nil)
        #expect(SSEParser.event(fromLine: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#) == nil)
        #expect(SSEParser.event(fromLine: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#) == nil)
    }

    @Test func emptyTextBlockStartIsIgnored() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#) == nil)
    }

    @Test func fallbackBlockIsReported() {
        let line = #"data: {"type":"content_block_start","index":0,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"}}}"#
        #expect(SSEParser.event(fromLine: line) == .fallback(fromModel: "claude-opus-5-5", toModel: "claude-opus-4-8"))
    }

    @Test func messageDeltaStopReasonAndRefusalCategory() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":12}}"#)
            == .messageDelta(stopReason: "end_turn", refusalCategory: nil))
        #expect(SSEParser.event(fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}}"#)
            == .messageDelta(stopReason: "refusal", refusalCategory: "cyber"))
    }

    @Test func stopAndErrorEvents() {
        #expect(SSEParser.event(fromLine: #"data: {"type":"message_stop"}"#) == .messageStop)
        #expect(SSEParser.event(fromLine: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
            == .error(type: "overloaded_error", message: "Overloaded"))
    }

    @Test func nonDataLinesPingsAndGarbageGiveNil() {
        #expect(SSEParser.event(fromLine: "event: content_block_delta") == nil)
        #expect(SSEParser.event(fromLine: "") == nil)
        #expect(SSEParser.event(fromLine: ": comment") == nil)
        #expect(SSEParser.event(fromLine: #"data: {"type": "ping"}"#) == nil)
        #expect(SSEParser.event(fromLine: "data: {broken") == nil)
    }
}

@Suite struct StreamAccumulatorTests {
    private func run(_ events: [StreamEvent]) -> StreamAccumulator {
        var accumulator = StreamAccumulator()
        events.forEach { accumulator.apply($0) }
        return accumulator
    }

    @Test func normalCompletionJoinsTextAndTrims() {
        let accumulator = run([.messageStart(model: "claude-opus-5-5"), .textDelta("Mer"), .textDelta("haba\n"),
                               .messageDelta(stopReason: "end_turn", refusalCategory: nil), .messageStop])
        #expect(accumulator.text == "Merhaba\n")
        #expect(accumulator.model == "claude-opus-5-5")
        #expect(accumulator.outcome == .completed(text: "Merhaba", truncated: false))
    }

    @Test func maxTokensMarksTruncation() {
        let outcome = run([.textDelta("uzun"), .messageDelta(stopReason: "max_tokens", refusalCategory: nil), .messageStop]).outcome
        #expect(outcome == .completed(text: "uzun", truncated: true))
    }

    @Test func refusalHidesPartialText() {
        let outcome = run([.textDelta("yarım"), .messageDelta(stopReason: "refusal", refusalCategory: "bio"), .messageStop]).outcome
        #expect(outcome == .refused(category: "bio"))
    }

    @Test func midStreamFallbackKeepsTextAndSwitchesModel() {
        let accumulator = run([.messageStart(model: "claude-opus-5-5"), .textDelta("Başlangıç "),
                               .fallback(fromModel: "claude-opus-5-5", toModel: "claude-opus-4-8"),
                               .textDelta("devamı"), .messageDelta(stopReason: "end_turn", refusalCategory: nil), .messageStop])
        #expect(accumulator.model == "claude-opus-4-8")
        #expect(accumulator.outcome == .completed(text: "Başlangıç devamı", truncated: false))
    }

    @Test func errorEventFails() {
        let outcome = run([.textDelta("a"), .error(type: "overloaded_error", message: "Overloaded")]).outcome
        #expect(outcome == .failed(.stream(type: "overloaded_error", message: "Overloaded"), partialText: "a"))
    }

    @Test func missingMessageStopIsIncomplete() {
        #expect(run([.textDelta("a")]).outcome == .incomplete(partialText: "a"))
    }
}

@Suite struct GlanceErrorTests {
    @Test func parsesAPIErrorBody() {
        let body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        #expect(GlanceError.fromHTTP(status: 401, body: body)
            == .http(status: 401, type: "authentication_error", message: "invalid x-api-key"))
        #expect(GlanceError.fromHTTP(status: 502, body: Data("<html>".utf8)) == .http(status: 502, type: nil, message: nil))
    }

    @Test func statusCodesGetSpecificTurkishMessages() {
        #expect(GlanceError.http(status: 401, type: nil, message: nil).userMessage.contains("API anahtarı geçersiz"))
        #expect(GlanceError.http(status: 404, type: nil, message: nil).userMessage.contains("\"model\""))
        #expect(GlanceError.http(status: 429, type: nil, message: nil).userMessage.contains("429"))
        #expect(GlanceError.http(status: 529, type: nil, message: nil).userMessage.contains("yoğun"))
        let withDetail = GlanceError.http(status: 400, type: "invalid_request_error", message: "bad field").userMessage
        #expect(withDetail.contains("invalid_request_error: bad field"))
    }

    @Test func cancellationIsNormalised() {
        #expect(GlanceError.wrap(URLError(.cancelled)) is CancellationError)
        #expect(GlanceError.wrap(CancellationError()) is CancellationError)
        let offline = GlanceError.wrap(URLError(.notConnectedToInternet)) as? GlanceError
        #expect(offline?.userMessage == "İnternet bağlantısı yok ya da koptu.")
        #expect(GlanceError.wrap(GlanceError.missingAPIKey) as? GlanceError == .missingAPIKey)
    }
}
