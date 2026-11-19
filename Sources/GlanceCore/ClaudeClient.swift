import Foundation

public protocol ResponseStreaming: Sendable {
    func stream(imageJPEG: Data, config: AppConfig, apiKey: String) -> AsyncThrowingStream<StreamEvent, any Error>
}

/// Streams a Messages API response over `URLSession`. Cancelling the consumer cancels the HTTP request.
public struct ClaudeClient: ResponseStreaming {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(imageJPEG: Data, config: AppConfig, apiKey: String) -> AsyncThrowingStream<StreamEvent, any Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try ClaudeAPI.makeRequest(imageJPEG: imageJPEG, config: config, apiKey: apiKey)
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 65_536 { break }
                        }
                        throw GlanceError.fromHTTP(status: status, body: body)
                    }
                    for try await line in bytes.lines {
                        if let event = SSEParser.event(fromLine: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: GlanceError.wrap(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
