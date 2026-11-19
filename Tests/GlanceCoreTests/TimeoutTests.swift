import Foundation
import Testing
@testable import GlanceCore

@Suite(.timeLimit(.minutes(1))) struct TimeoutTests {
    @Test func returnsTheValueWhenFastEnough() async throws {
        let value = try await withTimeout(seconds: 5, timeoutError: .captureFailed("süre doldu")) { 42 }
        #expect(value == 42)
    }

    /// A stuck call that ignores cancellation and only finishes after the deadline.
    private func lateFinish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { continuation.resume() }
        }
    }

    /// Waits for the late result and a little beyond, so a double resume would crash the run.
    private func waitForLateResult(_ finished: Counter) async throws {
        for _ in 0..<400 where finished.value == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func givesUpOnTimeAndDropsTheLateValue() async throws {
        let finished = Counter()
        await #expect(throws: GlanceError.captureFailed("süre doldu")) {
            try await withTimeout(seconds: 0.05, timeoutError: .captureFailed("süre doldu")) {
                await lateFinish()
                finished.increment()
                return 1
            }
        }
        try await waitForLateResult(finished)
        #expect(finished.value == 1)
    }

    @Test func dropsALateFailureToo() async throws {
        let finished = Counter()
        await #expect(throws: GlanceError.captureFailed("süre doldu")) {
            try await withTimeout(seconds: 0.05, timeoutError: .captureFailed("süre doldu")) { () async throws -> Int in
                await lateFinish()
                finished.increment()
                throw GlanceError.screenPermissionDenied
            }
        }
        try await waitForLateResult(finished)
        #expect(finished.value == 1)
    }

    @Test func passesOperationErrorsThrough() async {
        await #expect(throws: GlanceError.screenPermissionDenied) {
            try await withTimeout(seconds: 5, timeoutError: .captureFailed("süre doldu")) { () async throws -> Int in
                throw GlanceError.screenPermissionDenied
            }
        }
    }

    @Test func onlyTheFirstResultCounts() {
        let once = ResumeOnce()
        #expect(once.claim())
        #expect(!once.claim())
        #expect(!once.claim())
    }
}
