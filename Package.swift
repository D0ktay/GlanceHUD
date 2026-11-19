// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlanceHUD",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that does not need AppKit: config, API request/stream handling, controller logic.
        .target(name: "GlanceCore"),
        // The AppKit shell: HUD window, Carbon hotkeys, ScreenCaptureKit, menu bar item.
        .executableTarget(name: "GlanceHUD", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
