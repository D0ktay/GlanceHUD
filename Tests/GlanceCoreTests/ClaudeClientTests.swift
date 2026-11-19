import Foundation
import Testing
@testable import GlanceCore

/// Answers every request in-process. The scenario is picked from the `x-api-key` header so tests can run in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let sseBody = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","model":"claude-opus-5-5","content":[]}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        event: ping
        data: {"type": "ping"}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Merhaba"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" dünya"}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}

        event: message_stop
        data: {"type":"message_stop"}


        """

    /// `stopLoading` calls for "hang" requests, which never finish on their own.
    static let hangStops = Counter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.value(forHTTPHeaderField: "x-api-key") == "hang" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // URLSession holds back the first 512 bytes for content sniffing, so lead with an SSE comment as padding.
            let padding = ": " + String(repeating: " ", count: 600) + "\n"
            let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}"#
            client?.urlProtocol(self, didLoad: Data((padding + line + "\n\n").utf8))
            return // keep the connection open
        }
        let status: Int
        let body: String
        switch request.value(forHTTPHeaderField: "x-api-key") {
        case "ok":
            status = 200
            body = Self.sseBody
        case "bad":
            status = 401
            body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        default:
            status = 529
            body = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        if request.value(forHTTPHeaderField: "x-api-key") == "hang" {
            Self.hangStops.increment()
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}

@Suite(.timeLimit(.minutes(1))) struct ClaudeClientTests {
    private let client: ClaudeClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ClaudeClient(session: URLSession(configuration: configuration))
    }()

    private func collect(apiKey: String) async throws -> [StreamEvent] {
        var events: [StreamEvent] = []
        for try await event in client.stream(imageJPEG: Data([0xFF, 0xD8]), config: .default, apiKey: apiKey) {
            events.append(event)
        }
        return events
    }

    @Test func streamsParsedEvents() async throws {
        let events = try await collect(apiKey: "ok")
        #expect(events == [
            .messageStart(model: "claude-opus-5-5"),
            .textDelta("Merhaba"),
            .textDelta(" dünya"),
            .messageDelta(stopReason: "end_turn", refusalCategory: nil),
            .messageStop,
        ])
    }

    @Test func stoppingTheConsumerCancelsTheHTTPRequest() async throws {
        let client = client
        let stopsBefore = StubURLProtocol.hangStops.value
        let received = Counter()
        let consumer = Task {
            for try await _ in client.stream(imageJPEG: Data([0xFF, 0xD8]), config: .default, apiKey: "hang") {
                received.increment()
            }
        }
        try await waitUntil { received.value == 1 }
        #expect(received.value == 1)
        #expect(StubURLProtocol.hangStops.value == stopsBefore)

        consumer.cancel()
        _ = await consumer.result
        try await waitUntil { StubURLProtocol.hangStops.value > stopsBefore }
        #expect(StubURLProtocol.hangStops.value > stopsBefore)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func httpErrorBecomesGlanceError() async {
        await #expect(throws: GlanceError.http(status: 401, type: "authentication_error", message: "invalid x-api-key")) {
            _ = try await collect(apiKey: "bad")
        }
        await #expect(throws: GlanceError.http(status: 529, type: "overloaded_error", message: "Overloaded")) {
            _ = try await collect(apiKey: "busy")
        }
    }
}
