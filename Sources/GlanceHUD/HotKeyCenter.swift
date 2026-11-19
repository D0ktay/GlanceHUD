import Carbon.HIToolbox
import GlanceCore

/// System-wide hotkeys through the Carbon Event Manager. Unlike an event tap this needs no
/// Accessibility permission and never touches the focused app's events.
@MainActor
final class HotKeyCenter {
    private static let signature: OSType = 0x474C_4E43 // 'GLNC'

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    /// Registers `spec`; returns `noErr` or the Carbon status (e.g. `eventHotKeyExistsErr`).
    func register(_ spec: HotKeySpec, action: @escaping @MainActor () -> Void) -> OSStatus {
        let installStatus = installHandlerIfNeeded()
        guard installStatus == noErr else { return installStatus }

        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode, spec.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return status }
        hotKeyRefs.append(ref)
        actions[id] = action
        return noErr
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard handlerRef == nil else { return noErr }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The center lives as long as the app delegate, so an unretained pointer is safe.
        let context = Unmanaged.passUnretained(self).toOpaque()
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            // Application-target Carbon events are dispatched on the main thread.
            MainActor.assumeIsolated { center.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }
}
