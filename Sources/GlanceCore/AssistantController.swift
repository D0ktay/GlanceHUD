import Foundation

public protocol ScreenCapturing: Sendable {
    func captureJPEG(maxLongEdge: Int, quality: Double, cropRect: CaptureRect?) async throws -> Data
}

@MainActor
public protocol HUDDisplaying: AnyObject {
    func render(_ content: HUDContent)
    func setVisible(_ visible: Bool)
}

@MainActor
public protocol CancelToken: AnyObject {
    func cancel()
}

@MainActor
public protocol AutoHideScheduling {
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any CancelToken
}

public struct HUDContent: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case empty, waiting, streaming, done, failed, notice
    }

    public var phase: Phase
    public var body: String
    public var footer: String

    public init(phase: Phase, body: String, footer: String) {
        self.phase = phase
        self.body = body
        self.footer = footer
    }

    /// Body is a hint rather than an answer, so the HUD draws it dimmed.
    public var isPlaceholder: Bool { phase == .empty || phase == .waiting }

    public static let empty = HUDContent(phase: .empty, body: UIText.noResponseYet, footer: UIText.footerIdle)
}

/// Owns the HUD state: what text is held in memory, whether the window is up, and the auto-hide timer.
///
/// - `trigger()` hides whatever is on screen, captures the screen and streams Claude's answer into memory.
///   By default nothing appears by itself, not even errors: the user calls the HUD up with ⌃,. With
///   `autoShow` the HUD appears with the first words of the answer (or with an error) and auto-hides when done.
/// - `toggleVisibility()` only shows or hides the window; it never starts a request or clears the text.
///   Showing it this way pins it, so auto-hide stays off until the next trigger.
@MainActor
public final class AssistantController {
    public struct Settings: Sendable {
        public var config: AppConfig
        public var apiKey: String?
        /// Set when the config file could not be read and the defaults are in use.
        public var warning: String?

        public init(config: AppConfig, apiKey: String?, warning: String? = nil) {
            self.config = config
            self.apiKey = apiKey
            self.warning = warning
        }
    }

    public private(set) var content: HUDContent = .empty
    public private(set) var isVisible = false

    private let capturer: any ScreenCapturing
    private let streamer: any ResponseStreaming
    private let display: any HUDDisplaying
    private let scheduler: any AutoHideScheduling
    private let settings: @MainActor () -> Settings

    private var isPinned = false
    private var isRequestRunning = false
    /// Set by a trigger; the HUD shows itself when the answer starts unless the user toggled it meanwhile.
    private var revealsWhenAnswerStarts = false
    private var generation = 0
    private var requestTask: Task<Void, Never>?
    private var autoHideToken: (any CancelToken)?
    private var autoHideSeconds = AppConfig.default.autoHideSeconds
    private var configWarning: String?

    public init(
        capturer: any ScreenCapturing,
        streamer: any ResponseStreaming,
        display: any HUDDisplaying,
        scheduler: any AutoHideScheduling,
        settings: @escaping @MainActor () -> Settings
    ) {
        self.capturer = capturer
        self.streamer = streamer
        self.display = display
        self.scheduler = scheduler
        self.settings = settings
        display.render(content)
    }

    /// Starts a fresh capture-and-ask cycle, abandoning any request still in flight.
    @discardableResult
    public func trigger() -> Task<Void, Never> {
        requestTask?.cancel()
        cancelAutoHide()
        generation += 1
        let id = generation
        let current = settings()
        autoHideSeconds = current.config.autoHideSeconds
        configWarning = current.warning
        isPinned = false
        // Whatever is on screen goes away now.
        hide()

        guard let apiKey = current.apiKey else {
            isRequestRunning = false
            revealsWhenAnswerStarts = false
            update(HUDContent(phase: .failed, body: GlanceError.missingAPIKey.userMessage, footer: UIText.footerFailed))
            if current.config.autoShow {
                show()
                scheduleAutoHide(after: autoHideSeconds)
            }
            requestTask = nil
            return Task {}
        }

        // What ⌃, shows if pressed before the answer starts, instead of the previous answer.
        update(HUDContent(phase: .waiting, body: UIText.waiting,
                          footer: UIText.footerWaiting(model: current.config.model)))
        isRequestRunning = true
        // The answer waits for ⌃,, unless autoShow lets it show itself once it starts arriving.
        revealsWhenAnswerStarts = current.config.autoShow
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(id, config: current.config, apiKey: apiKey)
        }
        requestTask = task
        return task
    }

    public func toggleVisibility() {
        cancelAutoHide()
        revealsWhenAnswerStarts = false
        if isVisible {
            hide()
        } else {
            isPinned = true
            show()
        }
    }

    /// Shows a status message (startup readiness, setup problems). Ignored while a request is running.
    public func showNotice(_ text: String, seconds: Double) {
        guard !isRequestRunning else { return }
        cancelAutoHide()
        isPinned = false
        update(HUDContent(phase: .notice, body: text, footer: UIText.footerNotice))
        show()
        scheduleAutoHide(after: seconds)
    }

    private func run(_ id: Int, config: AppConfig, apiKey: String) async {
        var accumulator = StreamAccumulator()
        do {
            let jpeg = try await capturer.captureJPEG(maxLongEdge: config.maxImageLongEdge,
                                                      quality: config.jpegQuality, cropRect: config.captureRect)
            guard id == generation else { return }

            for try await event in streamer.stream(imageJPEG: jpeg, config: config, apiKey: apiKey) {
                guard id == generation else { return }
                accumulator.apply(event)
                // Leading blank lines would open a nearly empty HUD; wait for real text.
                let visibleText = accumulator.text.trimmed
                if !visibleText.isEmpty {
                    update(HUDContent(phase: .streaming, body: visibleText,
                                      footer: UIText.footerStreaming(model: accumulator.model ?? config.model)))
                    revealIfWaiting()
                }
            }
            guard id == generation else { return }
            finish(accumulator.outcome, model: accumulator.model ?? config.model)
        } catch {
            // A superseded request was cancelled on purpose; a cancellation of the current one was not.
            guard id == generation else { return }
            let message = error is CancellationError
                ? UIText.incomplete
                : (error as? GlanceError)?.userMessage ?? error.localizedDescription
            // Keep whatever text already arrived, as the incomplete-stream path does.
            update(HUDContent(phase: .failed, body: Self.join(accumulator.text, message), footer: UIText.footerFailed))
            endRequest()
        }
    }

    private func finish(_ outcome: StreamOutcome, model: String) {
        switch outcome {
        case .completed(let text, let truncated):
            var body = text.isEmpty ? UIText.emptyAnswer : text
            if truncated { body += "\n" + UIText.truncatedNote }
            update(HUDContent(phase: .done, body: body, footer: UIText.footerDone(model: model)))
        case .refused(let category):
            update(HUDContent(phase: .failed, body: UIText.refused(category: category), footer: UIText.footerFailed))
        case .failed(let error, let partialText):
            update(HUDContent(phase: .failed, body: Self.join(partialText, error.userMessage), footer: UIText.footerFailed))
        case .incomplete(let partialText):
            update(HUDContent(phase: .failed, body: Self.join(partialText, UIText.incomplete), footer: UIText.footerFailed))
        }
        endRequest()
    }

    /// Errors and empty answers never stream text, so they reveal the HUD here.
    private func endRequest() {
        isRequestRunning = false
        revealIfWaiting()
        scheduleAutoHide(after: autoHideSeconds)
    }

    private func revealIfWaiting() {
        guard revealsWhenAnswerStarts else { return }
        revealsWhenAnswerStarts = false
        show()
    }

    private func update(_ newContent: HUDContent) {
        var newContent = newContent
        if let configWarning, newContent.phase != .notice {
            // The body is the one part of the HUD that is always drawn (the footer is off by default).
            newContent.body = newContent.phase == .failed
                ? configWarning + "\n\n" + newContent.body
                : "⚠ \(UIText.configWarningShort)\n" + newContent.body
        }
        content = newContent
        display.render(newContent)
    }

    private func show() {
        isVisible = true
        display.setVisible(true)
    }

    private func hide() {
        isVisible = false
        display.setVisible(false)
    }

    private func scheduleAutoHide(after seconds: Double) {
        cancelAutoHide()
        guard isVisible, !isPinned, seconds > 0 else { return }
        let id = generation
        autoHideToken = scheduler.schedule(after: seconds) { [weak self] in
            guard let self, self.generation == id, !self.isPinned, self.isVisible else { return }
            self.autoHideToken = nil
            self.hide()
        }
    }

    private func cancelAutoHide() {
        autoHideToken?.cancel()
        autoHideToken = nil
    }

    private static func join(_ partial: String, _ message: String) -> String {
        let partial = partial.trimmed
        return partial.isEmpty ? message : partial + "\n\n" + message
    }
}

/// Production scheduler backed by a main-actor `Task`.
public struct TaskScheduler: AutoHideScheduling {
    public init() {}

    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any CancelToken {
        TaskToken(task: Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }
}

@MainActor
private final class TaskToken: CancelToken {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}
