import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class TextInsertionService {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func insert(_ text: String, into targetApplication: NSRunningApplication?) throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard isAccessibilityTrusted else {
            requestAccessibilityPermission()
            throw VoiceFlowError.accessibilityPermissionMissing
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmedText, forType: .string)

        if let targetApplication {
            targetApplication.activate(options: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        try postPasteShortcut()
    }

    private func postPasteShortcut() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            throw VoiceFlowError.textInsertionFailed
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
