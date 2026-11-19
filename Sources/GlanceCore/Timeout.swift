import Foundation

/// Runs `operation`, but throws `timeoutError` if it has not finished after `seconds`.
/// Unlike a task-group race this returns on time even when the operation ignores cancellation
/// (ScreenCaptureKit calls can); a late result is dropped.
public func withTimeout<T: Sendable>(
    seconds: Double,
    timeoutError: GlanceError,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let once = ResumeOnce()
    return try await withCheckedThrowingContinuation { continuation in
        let work = Task {
            do {
                let value = try await operation()
                if once.claim() { continuation.resume(returning: value) }
            } catch {
                if once.claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if once.claim() {
                work.cancel()
                continuation.resume(throwing: timeoutError)
            }
        }
    }
}

/// Lets exactly one of several racing callers resume a continuation.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
