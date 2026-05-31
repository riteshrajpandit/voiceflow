import Carbon.HIToolbox
import SwiftUI

struct ShortcutDefinition: Codable, Equatable, Hashable {
    var key: String
    var modifiers: ShortcutModifiers

    static let defaultStart = ShortcutDefinition(key: "J", modifiers: [.control, .shift])
    static let defaultStop = ShortcutDefinition(key: "K", modifiers: [.control, .shift])

    var displayText: String {
        modifiers.displayPrefix + key.uppercased()
    }

    var carbonKeyCode: UInt32? {
        Self.carbonKeyCodes[key.uppercased()]
    }

    var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(key.lowercased()))
    }

    var eventModifiers: SwiftUI.EventModifiers {
        modifiers.eventModifiers
    }

    func save(to key: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load(from key: String) -> ShortcutDefinition? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ShortcutDefinition.self, from: data)
    }

    private static let carbonKeyCodes: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9)
    ]
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)

    static let allCases: [ShortcutModifiers] = [.command, .control, .option, .shift]

    var displayPrefix: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Control") }
        if contains(.shift) { parts.append("Shift") }
        if contains(.option) { parts.append("Option") }
        if contains(.command) { parts.append("Command") }
        return parts.isEmpty ? "" : parts.joined(separator: " + ") + " + "
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers = SwiftUI.EventModifiers()
        if contains(.command) { modifiers.insert(.command) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}

final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var registeredHotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1

    func register(_ shortcut: ShortcutDefinition, action: @escaping () -> Void) {
        guard let keyCode = shortcut.carbonKeyCode else { return }
        installEventHandlerIfNeeded()

        let identifier = nextIdentifier
        nextIdentifier += 1
        let hotKeyID = EventHotKeyID(signature: OSType("VFLW".fourCharacterCode), id: identifier)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        guard status == noErr, let hotKeyRef else { return }
        handlers[identifier] = action
        registeredHotKeys.append(hotKeyRef)
    }

    func unregisterAll() {
        registeredHotKeys.forEach { UnregisterEventHotKey($0) }
        registeredHotKeys.removeAll()
        handlers.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
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
            guard status == noErr else { return status }

            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
    }
}

private extension String {
    var fourCharacterCode: FourCharCode {
        utf8.reduce(0) { result, character in
            (result << 8) + FourCharCode(character)
        }
    }
}
