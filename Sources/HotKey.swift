import Carbon
import Foundation

/// A system-wide keyboard shortcut. Works in every app and needs no permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        HotKey.actions[id] = action
        HotKey.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052_5046), id: id)   // 'PRPF'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            if status == noErr {
                let id = pressed.id
                DispatchQueue.main.async { HotKey.actions[id]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
