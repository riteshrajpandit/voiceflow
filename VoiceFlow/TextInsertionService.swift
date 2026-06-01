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
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(trimmedText, forType: .string)
        let dictatedPasteboardChange = pasteboard.changeCount

        if let targetApplication {
            targetApplication.activate(options: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        try postPasteShortcut()
        restorePasteboard(snapshot, ifUnchangedFrom: dictatedPasteboardChange)
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot, ifUnchangedFrom changeCount: Int) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard NSPasteboard.general.changeCount == changeCount else { return }
            snapshot.restore(to: NSPasteboard.general)
        }
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

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                representations[type] = item.data(forType: type)
            }
            return representations
        }.filter { !$0.isEmpty }

        return PasteboardSnapshot(items: copiedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
