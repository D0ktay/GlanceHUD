import AppKit
import GlanceCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "io.github.d0ktay.GlanceHUD", category: "app")
    private let store = ConfigStore()
    private let hotKeys = HotKeyCenter()
    private var config = AppConfig.default
    private var hud: HUDWindowController?
    private var controller: AssistantController?
    private var statusMenu: StatusMenu?
    private var calibration: CalibrationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            exit(writeSnapshot(to: arguments[index + 1]) ? 0 : 1)
        }
        // `GlanceHUD --calibrate` shows only the region picker, saves the result and quits.
        if arguments.contains("--calibrate") {
            runCalibration { [store] rect in
                if let rect { try? store.writeCaptureRect(rect) }
                NSApp.terminate(nil)
            }
            return
        }

        var problems: [String] = []
        do {
            try store.writeDefaultIfMissing()
        } catch {
            log.error("Could not write default config: \(error.localizedDescription, privacy: .public)")
        }
        let loaded = store.load()
        config = loaded.config
        if let warning = loaded.warning { problems.append(warning) }

        let hud = HUDWindowController(style: { [unowned self] in self.config })
        let controller = AssistantController(
            capturer: ScreenCapturer(),
            streamer: ClaudeClient(),
            display: hud,
            scheduler: TaskScheduler(),
            settings: { [unowned self] in self.reloadSettings() }
        )
        self.hud = hud
        self.controller = controller

        let triggerStatus = hotKeys.register(.trigger) { [weak controller] in _ = controller?.trigger() }
        let triggerAltStatus = hotKeys.register(.triggerAlternate) { [weak controller] in _ = controller?.trigger() }
        let toggleStatus = hotKeys.register(.toggle) { [weak controller] in controller?.toggleVisibility() }
        log.notice("Hotkeys registered: trigger=\(triggerStatus) triggerAlt=\(triggerAltStatus) toggle=\(toggleStatus)")
        if triggerStatus != noErr { problems.append(UIText.hotKeyFailed(label: HotKeySpec.trigger.label, status: triggerStatus)) }
        if triggerAltStatus != noErr { problems.append(UIText.hotKeyFailed(label: HotKeySpec.triggerAlternate.label, status: triggerAltStatus)) }
        if toggleStatus != noErr { problems.append(UIText.hotKeyFailed(label: HotKeySpec.toggle.label, status: toggleStatus)) }
        let fontKeys: [(HotKeySpec, @MainActor (Double) -> Double)] = [
            (.fontLarger, { AppConfig.steppedFontSize($0, by: 1) }),
            (.fontSmaller, { AppConfig.steppedFontSize($0, by: -1) }),
            (.fontReset, { _ in AppConfig.baseFontSize }),
        ]
        for (spec, newSize) in fontKeys {
            let status = hotKeys.register(spec) { [weak self] in self?.changeFontSize(newSize) }
            if status != noErr { problems.append(UIText.hotKeyFailed(label: spec.label, status: status)) }
        }
        let quitStatus = hotKeys.register(.quit) { NSApp.terminate(nil) }
        if quitStatus != noErr { problems.append(UIText.hotKeyFailed(label: HotKeySpec.quit.label, status: quitStatus)) }
        problems += shortcutConflicts()

        if reloadSettings().apiKey == nil { problems.append(UIText.missingAPIKey) }

        if config.showMenuBarIcon {
            statusMenu = StatusMenu(actions: .init(
                trigger: { [weak controller] in _ = controller?.trigger() },
                toggle: { [weak controller] in controller?.toggleVisibility() },
                calibrate: { [weak self] in self?.calibrateFromMenu() },
                captureFullScreen: { [weak self] in self?.captureFullScreen() },
                openConfig: { [weak self] in self?.openConfig() }
            ))
        }

        if problems.isEmpty {
            controller.showNotice(UIText.ready, seconds: 4)
        } else {
            controller.showNotice(problems.joined(separator: "\n\n"), seconds: 20)
        }
    }

    /// Re-read on every trigger, so edits to the config file apply without a relaunch.
    private func reloadSettings() -> AssistantController.Settings {
        let loaded = store.load()
        config = loaded.config
        let key = APIKeySource.resolve(
            environment: ProcessInfo.processInfo.environment,
            keychain: APIKeySource.readKeychain,
            config: config
        )
        return .init(config: config, apiKey: key, warning: loaded.warning)
    }

    /// Saves the new size to the config file, so it sticks, and redraws the HUD if it is up.
    private func changeFontSize(_ newSize: (Double) -> Double) {
        let current = store.load().config.fontSize
        let next = newSize(current)
        guard next != current else { return }
        do {
            try store.writeFontSize(next)
        } catch {
            log.error("Could not save font size: \(error.localizedDescription, privacy: .public)")
            return
        }
        config = store.load().config
        hud?.restyle()
    }

    private func shortcutConflicts() -> [String] {
        let table = SymbolicHotKeys.readTable()
        return HotKeySpec.all
            .filter { !SymbolicHotKeys.conflicts(for: $0, in: table).isEmpty }
            .map { UIText.shortcutConflict(label: $0.label) }
    }

    /// Opens the region picker on the main display; `finish` receives the chosen rect, or nil if cancelled.
    private func runCalibration(then finish: @escaping (CaptureRect?) -> Void) {
        guard let screen = NSScreen.screens.first else { finish(nil); return }
        let controller = CalibrationController(screen: screen) { [weak self] rect in
            self?.calibration = nil
            finish(rect)
        }
        calibration = controller
        controller.begin()
    }

    private func calibrateFromMenu() {
        runCalibration { [weak self] rect in
            guard let self, let rect else { return }
            do {
                try self.store.writeCaptureRect(rect)
                self.controller?.showNotice(UIText.regionSaved, seconds: 6)
            } catch {
                self.log.error("Could not save capture region: \(error.localizedDescription, privacy: .public)")
                self.controller?.showNotice(UIText.regionFailed, seconds: 6)
            }
        }
    }

    private func captureFullScreen() {
        do {
            try store.writeCaptureRect(nil)
            controller?.showNotice(UIText.regionCleared, seconds: 5)
        } catch {
            log.error("Could not clear capture region: \(error.localizedDescription, privacy: .public)")
            controller?.showNotice(UIText.regionFailed, seconds: 5)
        }
    }

    private func openConfig() {
        _ = try? store.writeDefaultIfMissing()
        if !NSWorkspace.shared.open(store.fileURL) {
            NSWorkspace.shared.open(
                [store.fileURL],
                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    /// `GlanceHUD --snapshot out.png` renders a sample HUD to a PNG and exits (no permissions needed).
    private func writeSnapshot(to path: String) -> Bool {
        let hud = HUDWindowController(style: { .default })
        hud.render(HUDContent(
            phase: .done,
            body: """
                Ekrandaki hata: "let" ile tanımlanan dizi değiştirilmeye çalışılıyor.

                Çözüm:
                - 12. satırda "let items" yerine "var items" yazın.
                - Ya da yeni bir dizi oluşturun:
                    let updated = items + [newItem]

                Sonra yeniden derleyin.
                """,
            footer: UIText.footerDone(model: AppConfig.default.model)
        ))
        guard let png = hud.snapshotPNG() else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
