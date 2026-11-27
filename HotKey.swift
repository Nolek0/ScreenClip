import Carbon
import Foundation

/// One global keyboard shortcut (works while other apps are in front, no Accessibility permission needed).
final class HotKey {
    static let shared = HotKey()

    struct Preset {
        let label: String
        let keyCode: UInt32
        let modifiers: UInt32
    }
    static let presets: [Preset] = [
        Preset(label: "⌘⇧7", keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | shiftKey)),
        Preset(label: "⌘⇧8", keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(cmdKey | shiftKey)),
        Preset(label: "⌘⇧9", keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | shiftKey)),
        Preset(label: "⌃⌥⌘R", keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey | cmdKey)),
        Preset(label: "⌥⇧R", keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey)),
    ]

    static var currentPreset: Preset {
        let i = UserDefaults.standard.integer(forKey: "recordHotkey")
        return presets.indices.contains(i) ? presets[i] : presets[0]
    }

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ preset: Preset) {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5343_4C50), id: 1)  // "SCLP"
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
