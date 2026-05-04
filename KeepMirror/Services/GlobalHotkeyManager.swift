import Carbon.HIToolbox
import Foundation

// MARK: - GlobalHotkeyManager
//
// Registers a system-wide keyboard shortcut using the Carbon EventHotKey API.
// Works WITHOUT Accessibility / Input Monitoring permission.
// Supports runtime re-registration when the user changes the shortcut in Settings.

nonisolated(unsafe) private var _hotKeyCallback: (() -> Void)?

final class GlobalHotkeyManager {

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef:       EventHotKeyRef?
    private let onToggle: @MainActor () -> Void

    // MARK: Init / Deinit

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle
        _hotKeyCallback = { Task { @MainActor in onToggle() } }
        installHandler()
    }

    deinit {
        unregister()
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        _hotKeyCallback = nil
    }

    // MARK: - Public API

    /// Re-register with a new key/modifiers combo (call after user changes shortcut in Settings).
    func reconfigure(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        register(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Internal

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in _hotKeyCallback?(); return noErr },
            1, &spec, nil, &eventHandlerRef
        )
    }

    private func register(keyCode: UInt32 = UInt32(kVK_ANSI_M),
                          modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        var id = EventHotKeyID(signature: 0x6B6D6972, id: 1)
        RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }
}

// MARK: - HotkeyDescriptor (human-readable display of a hotkey)

struct HotkeyDescriptor {
    let keyCode:   UInt32
    let modifiers: UInt32

    /// Symbols string, e.g. "⌘⇧M"
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    /// Build from an NSEvent flags + key
    static func from(event: NSEvent.ModifierFlags, keyCode: UInt16, character: String) -> HotkeyDescriptor {
        var mods: UInt32 = 0
        if event.contains(.command)  { mods |= UInt32(cmdKey) }
        if event.contains(.shift)    { mods |= UInt32(shiftKey) }
        if event.contains(.option)   { mods |= UInt32(optionKey) }
        if event.contains(.control)  { mods |= UInt32(controlKey) }
        return HotkeyDescriptor(keyCode: UInt32(keyCode), modifiers: mods)
    }

    private func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"; case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"; case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"; case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"
        case kVK_Space:  return "Space"; case kVK_Tab: return "Tab"; case kVK_Return: return "↩"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"
        case kVK_F4: return "F4"; case kVK_F5: return "F5"; case kVK_F6: return "F6"
        default: return "?"
        }
    }
}

import AppKit   // for NSEventModifierFlags
