import Foundation
import Carbon

private let tesseraHotKeySignature: OSType = 0x54535241 // 'TSRA'

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr, hotKeyID.signature == tesseraHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let numericID = hotKeyID.id
    Task { @MainActor in
        HotkeyManager.shared.handleTriggeredHotKey(id: numericID)
    }
    return noErr
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()

    public var onActionTriggered: ((ShortcutAction) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var registeredRefs: [ShortcutAction: EventHotKeyRef] = [:]
    private var idToAction: [UInt32: ShortcutAction] = [:]

    public init() {
        installCarbonHandlerIfNeeded()
    }

    public func registerAll(from bindings: [ShortcutAction: KeyBinding]) {
        unregisterAll()
        installCarbonHandlerIfNeeded()

        for action in ShortcutAction.allCases {
            guard let binding = bindings[action] else { continue }
            let hotKeyID = EventHotKeyID(signature: tesseraHotKeySignature, id: action.hotKeyNumericID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registeredRefs[action] = ref
                idToAction[action.hotKeyNumericID] = action
            }
        }
    }

    public func unregisterAll() {
        for (_, ref) in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
        idToAction.removeAll()
    }

    fileprivate func handleTriggeredHotKey(id: UInt32) {
        guard let action = idToAction[id] else { return }
        onActionTriggered?(action)
    }

    private func installCarbonHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}

