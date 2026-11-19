import Foundation
import Testing
@testable import GlanceCore

// MARK: - Fakes

final class FakeCapturer: ScreenCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let error: GlanceError?

    init(error: GlanceError? = nil) {
        self.error = error
    }

    var calls: Int { lock.withLock { count } }

    func captureJPEG(maxLongEdge: Int, quality: Double, cropRect: CaptureRect?) async throws -> Data {
        lock.withLock { count += 1 }
        if let error { throw error }
        return Data([0xFF, 0xD8, 0xFF])
    }
}

/// Blocks every capture until the test releases it, like a slow ScreenCaptureKit call that ignores cancellation.
final class GatedCapturer: ScreenCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Data, any Error>] = []

    var started: Int { lock.withLock { waiters.count } }

    func captureJPEG(maxLongEdge: Int, quality: Double, cropRect: CaptureRect?) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
    }

    func release(_ index: Int) {
        guard let waiter = lock.withLock({ index < waiters.count ? waiters[index] : nil }) else {
            Issue.record("capture \(index) never started")
            return
        }
        waiter.resume(returning: Data([0xFF, 0xD8, 0xFF]))
    }
}

/// Replays a fixed list of events for every request, then ends with `error` if given.
final class ScriptedStreamer: ResponseStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let events: [StreamEvent]
    private let error: (any Error)?

    init(_ events: [StreamEvent], error: (any Error)? = nil) {
        self.events = events
        self.error = error
    }

    var calls: Int { lock.withLock { count } }

    func stream(imageJPEG: Data, config: AppConfig, apiKey: String) -> AsyncThrowingStream<StreamEvent, any Error> {
        lock.withLock { count += 1 }
        let events = events
        let error = error
        return AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish(throwing: error)
        }
    }

    static func answer(_ text: String) -> ScriptedStreamer {
        ScriptedStreamer([.messageStart(model: "claude-opus-5-5"), .textDelta(text),
                          .messageDelta(stopReason: "end_turn", refusalCategory: nil), .messageStop])
    }
}

/// Hands each request a stream the test feeds by hand.
final class ManualStreamer: ResponseStreaming, @unchecked Sendable {
    typealias Continuation = AsyncThrowingStream<StreamEvent, any Error>.Continuation
    private let lock = NSLock()
    private var continuations: [Continuation] = []
    private var terminated: Set<Int> = []

    var count: Int { lock.withLock { continuations.count } }

    func continuation(_ index: Int) -> Continuation { lock.withLock { continuations[index] } }

    /// True once the consumer stopped listening (cancelled) or the stream finished.
    func isTerminated(_ index: Int) -> Bool { lock.withLock { terminated.contains(index) } }

    func stream(imageJPEG: Data, config: AppConfig, apiKey: String) -> AsyncThrowingStream<StreamEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<StreamEvent, any Error>.makeStream()
        let index = lock.withLock {
            continuations.append(continuation)
            return continuations.count - 1
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.lock.withLock { self.terminated.insert(index) }
        }
        return stream
    }

    func answer(_ index: Int, _ text: String) {
        let continuation = continuation(index)
        continuation.yield(.textDelta(text))
        continuation.yield(.messageDelta(stopReason: "end_turn", refusalCategory: nil))
        continuation.yield(.messageStop)
        continuation.finish()
    }
}

@MainActor
final class FakeDisplay: HUDDisplaying {
    var visible = false
    var last: HUDContent?
    var history: [HUDContent] = []
    /// What actually reached the screen: renders while visible, plus the content at each show.
    var shown: [HUDContent] = []
    var visibilityChanges = 0

    func render(_ content: HUDContent) {
        last = content
        history.append(content)
        if visible { shown.append(content) }
    }

    func setVisible(_ visible: Bool) {
        if visible != self.visible { visibilityChanges += 1 }
        self.visible = visible
        if visible, let last { shown.append(last) }
    }
}

@MainActor
final class FakeToken: CancelToken {
    var cancelled = false
    func cancel() { cancelled = true }
}

@MainActor
final class FakeScheduler: AutoHideScheduling {
    var scheduled: [(seconds: Double, action: @MainActor () -> Void, token: FakeToken)] = []

    var pending: [Double] { scheduled.filter { !$0.token.cancelled }.map(\.seconds) }

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any CancelToken {
        let token = FakeToken()
        scheduled.append((seconds, action, token))
        return token
    }

    /// Runs every timer that is still armed, as if its time had passed.
    func fireAll() {
        for entry in scheduled where !entry.token.cancelled {
            entry.action()
        }
    }
}

// MARK: - Tests

@MainActor
@Suite(.timeLimit(.minutes(1))) struct AssistantControllerTests {
    let display = FakeDisplay()
    let scheduler = FakeScheduler()

    /// The opt-in mode where answers show themselves as they arrive.
    private static let autoShow: AppConfig = {
        var config = AppConfig.default
        config.autoShow = true
        return config
    }()

    private func makeController(
        capturer: any ScreenCapturing = FakeCapturer(),
        streamer: any ResponseStreaming,
        config: AppConfig = .default,
        apiKey: String? = "test-key",
        warning: String? = nil
    ) -> AssistantController {
        AssistantController(capturer: capturer, streamer: streamer, display: display, scheduler: scheduler,
                            settings: { .init(config: config, apiKey: apiKey, warning: warning) })
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: Default: everything waits for ⌃,

    @Test func answerWaitsForTheShowShortcut() async {
        let capturer = FakeCapturer()
        let streamer = ScriptedStreamer.answer("Yanıt burada")
        let controller = makeController(capturer: capturer, streamer: streamer)

        await controller.trigger().value
        #expect(capturer.calls == 1)
        #expect(streamer.calls == 1)
        #expect(!display.visible)
        #expect(display.shown.isEmpty)
        #expect(scheduler.scheduled.isEmpty)
        #expect(controller.content.phase == .done)
        #expect(controller.content.body == "Yanıt burada")
        #expect(controller.content.footer.contains("claude-opus-5-5"))

        controller.toggleVisibility()
        #expect(display.visible)
        #expect(display.last?.body == "Yanıt burada")
        #expect(scheduler.scheduled.isEmpty) // stays up until hidden again
        controller.toggleVisibility()
        #expect(!display.visible)
        #expect(capturer.calls == 1)
        #expect(streamer.calls == 1)
    }

    @Test func errorsAlsoWaitForTheShowShortcut() async {
        let streamer = ScriptedStreamer.answer("x")
        let controller = makeController(capturer: FakeCapturer(error: .screenPermissionDenied), streamer: streamer)
        await controller.trigger().value
        #expect(streamer.calls == 0)
        #expect(!display.visible)
        #expect(controller.content.phase == .failed)

        controller.toggleVisibility()
        #expect(display.visible)
        #expect(display.last?.body.contains("Ekran kaydı izni") == true)
    }

    @Test func missingKeyFailsWithoutCapturing() async {
        let capturer = FakeCapturer()
        let controller = makeController(capturer: capturer, streamer: ScriptedStreamer.answer("x"), apiKey: nil)
        await controller.trigger().value
        #expect(capturer.calls == 0)
        #expect(!display.visible)
        #expect(controller.content.phase == .failed)
        #expect(controller.content.body.contains("API anahtarı bulunamadı"))
    }

    @Test func triggerHidesWhatIsOnScreenAndKeepsItHidden() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer)
        let first = controller.trigger()
        await waitUntil { streamer.count == 1 }
        streamer.answer(0, "ilk")
        await first.value
        controller.toggleVisibility()
        #expect(display.visible)

        let second = controller.trigger()
        #expect(!display.visible)
        await waitUntil { streamer.count == 2 }
        streamer.answer(1, "ikinci")
        await second.value
        #expect(!display.visible)
        #expect(controller.content.body == "ikinci")
    }

    @Test func showingBeforeTheAnswerGivesPlaceholderThenTheAnswer() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer)
        let first = controller.trigger()
        await waitUntil { streamer.count == 1 }
        streamer.answer(0, "ilk")
        await first.value

        let second = controller.trigger()
        controller.toggleVisibility()
        #expect(display.visible)
        // Never the previous answer, which could pass for the new one.
        #expect(display.shown.map(\.phase) == [.waiting])
        #expect(display.last?.body == UIText.waiting)

        await waitUntil { streamer.count == 2 }
        streamer.answer(1, "ikinci")
        await second.value
        #expect(display.visible)
        #expect(display.last?.body == "ikinci")
        #expect(scheduler.pending.isEmpty)
    }

    @Test func toggleBeforeAnyAnswerShowsPlaceholder() {
        let controller = makeController(streamer: ScriptedStreamer.answer("x"))
        controller.toggleVisibility()
        #expect(display.visible)
        #expect(display.last == .empty)
        #expect(scheduler.scheduled.isEmpty)
    }

    // MARK: autoShow: answers show themselves

    @Test func autoShowRevealsWithTheAnswerThenAutoHides() async {
        let controller = makeController(streamer: ScriptedStreamer.answer("Yanıt burada"), config: Self.autoShow)
        let task = controller.trigger()
        #expect(!display.visible)
        await task.value

        #expect(display.visible)
        #expect(controller.content.phase == .done)
        #expect(controller.content.body == "Yanıt burada")
        #expect(scheduler.pending == [10])
        scheduler.fireAll()
        #expect(!display.visible)
        #expect(controller.content.body == "Yanıt burada")
    }

    @Test func autoShowNeverPutsAStatusOnScreen() async {
        let controller = makeController(streamer: ScriptedStreamer.answer("metin"), config: Self.autoShow)
        await controller.trigger().value
        #expect(!display.shown.isEmpty)
        #expect(display.shown.allSatisfy { $0.phase == .streaming || $0.phase == .done })
    }

    @Test func autoShowStreamsTextAsItArrives() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        let task = controller.trigger()
        await waitUntil { streamer.count == 1 }
        #expect(!display.visible)

        streamer.continuation(0).yield(.textDelta("ilk parça"))
        await waitUntil { display.visible }
        #expect(display.last?.phase == .streaming)
        #expect(display.last?.body == "ilk parça")
        #expect(display.last?.footer.contains("yazıyor") == true)

        streamer.answer(0, " ve son")
        await task.value
        #expect(controller.content.body == "ilk parça ve son")
    }

    @Test func autoShowHidesThePreviousAnswerUntilNewTextArrives() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        let first = controller.trigger()
        await waitUntil { streamer.count == 1 }
        streamer.answer(0, "ilk")
        await first.value
        #expect(display.visible)

        let second = controller.trigger()
        #expect(!display.visible)
        #expect(scheduler.pending.isEmpty)
        #expect(controller.content.phase == .waiting)

        await waitUntil { streamer.count == 2 }
        streamer.continuation(1).yield(.textDelta("ikinci"))
        await waitUntil { display.visible }
        #expect(display.last?.body == "ikinci")
        streamer.answer(1, "")
        await second.value
        #expect(controller.content.body == "ikinci")
    }

    @Test func blankLinesAloneDoNotOpenTheHUD() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        let task = controller.trigger()
        await waitUntil { streamer.count == 1 }

        streamer.continuation(0).yield(.textDelta("\n\n"))
        streamer.continuation(0).yield(.textDelta("metin"))
        await waitUntil { display.visible }
        #expect(display.history.filter { $0.phase == .streaming }.map(\.body) == ["metin"])

        streamer.answer(0, "")
        await task.value
        #expect(controller.content.body == "metin")
    }

    @Test func autoShowRevealsErrors() async {
        let streamer = ScriptedStreamer.answer("x")
        let controller = makeController(capturer: FakeCapturer(error: .screenPermissionDenied), streamer: streamer,
                                        config: Self.autoShow)
        await controller.trigger().value
        #expect(display.visible)
        #expect(controller.content.body.contains("Ekran kaydı izni"))
        #expect(scheduler.pending == [10])
    }

    @Test func autoShowRevealsAMissingKeyAtOnce() async {
        let controller = makeController(streamer: ScriptedStreamer.answer("x"), config: Self.autoShow, apiKey: nil)
        await controller.trigger().value
        #expect(display.visible)
        #expect(controller.content.body.contains("API anahtarı bulunamadı"))
    }

    @Test func autoShowRevealsAnEmptyAnswer() async {
        let streamer = ScriptedStreamer([.messageDelta(stopReason: "end_turn", refusalCategory: nil), .messageStop])
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        await controller.trigger().value
        #expect(display.visible)
        #expect(controller.content.body == UIText.emptyAnswer)
    }

    @Test func unexpectedCancellationStillEndsTheRequest() async {
        let controller = makeController(streamer: ScriptedStreamer([.textDelta("yarım")], error: CancellationError()),
                                        config: Self.autoShow)
        await controller.trigger().value
        #expect(display.visible)
        #expect(controller.content.phase == .failed)
        #expect(controller.content.body.hasPrefix("yarım"))
        #expect(controller.content.body.contains(UIText.incomplete))
        #expect(scheduler.pending == [10])
    }

    @Test func autoHideCanBeTurnedOff() async {
        var config = Self.autoShow
        config.autoHideSeconds = 0
        let controller = makeController(streamer: ScriptedStreamer.answer("metin"), config: config)
        await controller.trigger().value
        #expect(scheduler.scheduled.isEmpty)
        #expect(display.visible)
    }

    @Test func autoHideUsesConfiguredSeconds() async {
        var config = Self.autoShow
        config.autoHideSeconds = 25
        let controller = makeController(streamer: ScriptedStreamer.answer("metin"), config: config)
        await controller.trigger().value
        #expect(scheduler.pending == [25])
    }

    @Test func manualShowCancelsAutoHide() async {
        let controller = makeController(streamer: ScriptedStreamer.answer("metin"), config: Self.autoShow)
        await controller.trigger().value
        #expect(scheduler.pending == [10])

        controller.toggleVisibility() // hide
        controller.toggleVisibility() // show again, pinned
        #expect(scheduler.pending.isEmpty)
        scheduler.fireAll()
        #expect(display.visible)
    }

    @Test func manualShowDuringStreamingKeepsItUpAfterwards() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        let task = controller.trigger()
        await waitUntil { streamer.count == 1 }
        streamer.continuation(0).yield(.textDelta("ilk"))
        await waitUntil { display.visible }

        controller.toggleVisibility() // hide
        controller.toggleVisibility() // show again: pinned
        streamer.answer(0, " bitti")
        await task.value

        #expect(controller.content.body == "ilk bitti")
        #expect(scheduler.pending.isEmpty)
        scheduler.fireAll()
        #expect(display.visible)
    }

    @Test func hidingMidStreamKeepsItHidden() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        let task = controller.trigger()
        await waitUntil { streamer.count == 1 }
        streamer.continuation(0).yield(.textDelta("arka planda"))
        await waitUntil { display.visible }

        controller.toggleVisibility()
        streamer.answer(0, " geldi")
        await task.value

        #expect(!display.visible)
        #expect(scheduler.pending.isEmpty)
        #expect(controller.content.body == "arka planda geldi")
        controller.toggleVisibility()
        #expect(display.visible)
    }

    @Test func hidingAgainWhileWaitingIsRespected() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer, config: Self.autoShow)
        let task = controller.trigger()
        controller.toggleVisibility() // show the placeholder
        controller.toggleVisibility() // and hide it again: the user wants it out of the way

        await waitUntil { streamer.count == 1 }
        streamer.answer(0, "sessizce")
        await task.value
        #expect(!display.visible)
        #expect(controller.content.body == "sessizce")
        #expect(scheduler.pending.isEmpty)
    }

    // MARK: Content

    @Test func truncatedAnswerIsMarked() async {
        let streamer = ScriptedStreamer([.textDelta("uzun yanıt"), .messageDelta(stopReason: "max_tokens", refusalCategory: nil), .messageStop])
        let controller = makeController(streamer: streamer)
        await controller.trigger().value
        #expect(controller.content.phase == .done)
        #expect(controller.content.body.hasPrefix("uzun yanıt"))
        #expect(controller.content.body.contains(UIText.truncatedNote))
    }

    @Test func refusalReplacesPartialText() async {
        let streamer = ScriptedStreamer([.textDelta("yarım"), .messageDelta(stopReason: "refusal", refusalCategory: "cyber"), .messageStop])
        let controller = makeController(streamer: streamer)
        await controller.trigger().value
        #expect(controller.content.phase == .failed)
        #expect(!controller.content.body.contains("yarım"))
        #expect(controller.content.body.contains("cyber"))
    }

    @Test func brokenConfigWarningAccompaniesFailures() async {
        let controller = makeController(streamer: ScriptedStreamer.answer("x"), apiKey: nil,
                                        warning: "Ayar dosyası okunamadı")
        await controller.trigger().value
        #expect(controller.content.body.hasPrefix("Ayar dosyası okunamadı"))
        #expect(controller.content.body.contains("API anahtarı bulunamadı"))
    }

    @Test func brokenConfigWarningPrecedesTheAnswer() async {
        let controller = makeController(streamer: ScriptedStreamer.answer("metin"), warning: "Ayar dosyası okunamadı")
        await controller.trigger().value
        // In the body, because the footer is hidden by default.
        #expect(controller.content.body == "⚠ \(UIText.configWarningShort)\nmetin")
        #expect(display.history.filter { $0.phase == .streaming }.allSatisfy { $0.body.hasPrefix("⚠ ") })
    }

    // MARK: Overlapping requests

    @Test func newTriggerCancelsAndIgnoresTheOlderRequest() async {
        let capturer = FakeCapturer()
        let streamer = ManualStreamer()
        let controller = makeController(capturer: capturer, streamer: streamer, config: Self.autoShow)

        let first = controller.trigger()
        await waitUntil { streamer.count == 1 }
        let second = controller.trigger()
        await waitUntil { streamer.count == 2 && streamer.isTerminated(0) }
        // The superseded stream is dropped (which cancels its HTTP request) before it answers.
        #expect(streamer.isTerminated(0))

        streamer.answer(1, "yeni")
        await second.value
        streamer.answer(0, "eski") // the old answer arrives last and must lose
        await first.value

        #expect(capturer.calls == 2)
        #expect(controller.content.body == "yeni")
        #expect(!display.history.contains { $0.body.contains("eski") })
        #expect(!display.history.contains { $0.phase == .failed })
        #expect(scheduler.pending == [10])
    }

    @Test func captureFinishingAfterANewTriggerIsDropped() async {
        let capturer = GatedCapturer()
        let streamer = ManualStreamer()
        let controller = makeController(capturer: capturer, streamer: streamer)

        let first = controller.trigger()
        await waitUntil { capturer.started == 1 }
        let second = controller.trigger()
        await waitUntil { capturer.started == 2 }

        capturer.release(1)
        await waitUntil { streamer.count == 1 }
        capturer.release(0) // the superseded capture completes last
        await first.value
        #expect(streamer.count == 1)
        #expect(!display.history.contains { $0.phase == .failed })

        streamer.answer(0, "güncel")
        await second.value
        #expect(controller.content.body == "güncel")
    }

    // MARK: Notices

    @Test func noticeAutoHidesButNeverInterruptsARequest() async {
        let streamer = ManualStreamer()
        let controller = makeController(streamer: streamer)
        controller.showNotice("hazır", seconds: 4)
        #expect(display.visible)
        #expect(display.last?.body == "hazır")
        #expect(scheduler.pending == [4])

        let task = controller.trigger()
        #expect(!display.visible)
        #expect(scheduler.pending.isEmpty)
        controller.showNotice("araya girme", seconds: 4)
        #expect(!display.visible)
        #expect(!display.history.contains { $0.body == "araya girme" })

        await waitUntil { streamer.count == 1 }
        streamer.answer(0, "bitti")
        await task.value
        #expect(controller.content.body == "bitti")
    }
}
