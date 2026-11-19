import AppKit
import GlanceCore

/// Small menu bar item: the app has no Dock icon, so this is the visible way to reach settings or quit.
@MainActor
final class StatusMenu: NSObject {
    struct Actions {
        let trigger: @MainActor () -> Void
        let toggle: @MainActor () -> Void
        let calibrate: @MainActor () -> Void
        let captureFullScreen: @MainActor () -> Void
        let openConfig: @MainActor () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init()
        // The user's chosen blue (#2578B0), so the icon all but disappears.
        // A non-template image keeps its own color instead of following the menu bar.
        let blue = NSImage.SymbolConfiguration(paletteColors: [
            NSColor(srgbRed: 0x25 / 255.0, green: 0x78 / 255.0, blue: 0xB0 / 255.0, alpha: 1),
        ])
        let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "GlanceHUD")?
            .withSymbolConfiguration(blue)
        icon?.isTemplate = false
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.addItem(item(UIText.menuTrigger, #selector(trigger)))
        menu.addItem(item(UIText.menuToggle, #selector(toggle)))
        menu.addItem(.separator())
        menu.addItem(item(UIText.menuCalibrate, #selector(calibrate)))
        menu.addItem(item(UIText.menuFullScreen, #selector(captureFullScreen)))
        menu.addItem(.separator())
        menu.addItem(item("Ayar dosyasını aç", #selector(openConfig)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "GlanceHUD'dan çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func trigger() { actions.trigger() }
    @objc private func toggle() { actions.toggle() }
    @objc private func calibrate() { actions.calibrate() }
    @objc private func captureFullScreen() { actions.captureFullScreen() }
    @objc private func openConfig() { actions.openConfig() }
}
