import SwiftUI

struct ContentView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if model.hasCompletedStartupGuide {
                TranscriptionWorkspaceView()
            } else {
                StartupGuideView()
            }
        }
        .frame(minWidth: 940, minHeight: 620)
    }
}

private struct SidebarView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("VoiceFlow", systemImage: "waveform.and.mic")
                    .font(.title2.weight(.semibold))
                Text("Local voice to text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            StatusCardView()

            VStack(alignment: .leading, spacing: 10) {
                Text("Shortcuts")
                    .font(.headline)
                ShortcutRowView(title: "Start", shortcut: model.startShortcut)
                ShortcutRowView(title: "Stop", shortcut: model.stopShortcut)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Compliance")
                    .font(.headline)
                ComplianceRowView(icon: "lock.shield", text: "Audio stays on this Mac")
                ComplianceRowView(icon: "keyboard", text: model.isAccessibilityTrusted ? "Can paste into focused apps" : "Accessibility permission needed")
                ComplianceRowView(icon: "network.slash", text: "No cloud transcription path")
                ComplianceRowView(icon: "person.crop.circle.badge.checkmark", text: "Ask consent before recording others")
            }

            Spacer()

            Text(model.latestNotice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(22)
        .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 340)
    }
}

private struct StatusCardView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.status.systemImage)
                    .font(.title2)
                    .foregroundStyle(model.status.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.status.title)
                        .font(.headline)
                    Text(model.modelBundle.isAvailable ? "WhisperKit small.en bundle found" : "WhisperKit bundle missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                model.toggleRecording()
            } label: {
                Label(model.isRecording ? "Stop Recording" : "Start Recording", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .red : .accentColor)
            .disabled(model.isProcessing)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TranscriptionWorkspaceView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HeaderBarView()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Transcript")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        model.resetTranscript()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(model.transcript.isEmpty)
                }

                TextEditor(text: $model.transcript)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if model.transcript.isEmpty {
                            VStack {
                                Image(systemName: "text.bubble")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                                Text("Your transcribed text will appear here.")
                                    .foregroundStyle(.secondary)
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
            .padding(28)
        }
    }
}

private struct HeaderBarView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice capture")
                    .font(.title.weight(.semibold))
                Text("Use the keyboard shortcuts or menu bar icon to dictate into the focused app.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.startSystemWideRecording()
            } label: {
                Label("Start", systemImage: "mic.fill")
            }
            .keyboardShortcut(model.startShortcut.keyEquivalent, modifiers: model.startShortcut.eventModifiers)
            .disabled(model.isRecording || model.isProcessing)

            Button {
                model.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut(model.stopShortcut.keyEquivalent, modifiers: model.stopShortcut.eventModifiers)
            .disabled(!model.isRecording)
        }
        .padding(28)
    }
}

private struct StartupGuideView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Set up local transcription")
                        .font(.largeTitle.weight(.bold))
                    Text("VoiceFlow is designed for private, local dictation with an on-device WhisperKit Core ML model and explicit microphone control.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    GuideStepView(number: "1", title: "Confirm local model", detail: "VoiceFlow uses the speech model included with the app bundle for on-device transcription.")
                    GuideStepView(number: "2", title: "Grant microphone access", detail: "macOS prompts on first recording. Audio is captured only while you start a dictation session.")
                    GuideStepView(number: "3", title: "Approve Accessibility", detail: "VoiceFlow uses Accessibility only to paste your transcript into the focused text field after you stop recording.")
                    GuideStepView(number: "4", title: "Use shortcuts", detail: "Defaults are Control + Shift + J to start and Control + Shift + K to stop. You can change them in Settings.")
                    GuideStepView(number: "5", title: "Respect consent", detail: "Use transcription only where you have permission and avoid high-risk decisions from raw transcripts.")
                }

                PermissionReadinessView()
                ModelReadinessView()

                HStack {
                    Button {
                        model.completeStartupGuide()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
            .padding(34)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }
}

private struct PermissionReadinessView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: model.isAccessibilityTrusted ? "checkmark.seal.fill" : "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(model.isAccessibilityTrusted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(model.isAccessibilityTrusted ? "Accessibility permission ready" : "Accessibility permission required")
                    .font(.headline)
                Text("System-wide dictation uses Accessibility to paste your transcript into the focused text field. VoiceFlow does not read screen contents or keystrokes.")
                    .foregroundStyle(.secondary)
                if !model.isAccessibilityTrusted {
                    Button {
                        model.requestAccessibilityPermission()
                    } label: {
                        Label("Request Permission", systemImage: "gearshape")
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ModelReadinessView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.modelBundle.isAvailable ? "Model bundle detected" : "Model bundle not detected", systemImage: model.modelBundle.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(model.modelBundle.isAvailable ? .green : .orange)
            Text(model.modelBundle.displayPath)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("VoiceFlow loads this bundled model directly from the app resources and does not download speech models at runtime.")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GuideStepView: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingsView: View {
    @Environment(VoiceFlowModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Keyboard Shortcuts") {
                ShortcutPickerView(title: "Start recording", shortcut: $model.startShortcut)
                ShortcutPickerView(title: "Stop recording", shortcut: $model.stopShortcut)
            }

            Section("System-wide Dictation") {
                LabeledContent("Accessibility", value: model.isAccessibilityTrusted ? "Ready" : "Required")
                Text("Accessibility is used only to paste transcripts into the app you were using. Dictation text is temporarily placed on the clipboard and the previous clipboard is restored after paste when possible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.isAccessibilityTrusted {
                    Button("Request Accessibility Permission") {
                        model.requestAccessibilityPermission()
                    }
                }
            }

            Section("Model") {
                LabeledContent("Bundle status", value: model.modelBundle.isAvailable ? "Ready" : "Missing")
                Text(model.modelBundle.displayPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 300)
    }
}

private struct ShortcutPickerView: View {
    let title: String
    @Binding var shortcut: ShortcutDefinition

    private let keys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("Control", isOn: modifierBinding(.control))
            Toggle("Shift", isOn: modifierBinding(.shift))
            Toggle("Option", isOn: modifierBinding(.option))
            Toggle("Command", isOn: modifierBinding(.command))
            Picker("Key", selection: $shortcut.key) {
                ForEach(keys, id: \.self) { key in
                    Text(key).tag(key)
                }
            }
            .frame(width: 76)
            Text(shortcut.displayText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
    }

    private func modifierBinding(_ modifier: ShortcutModifiers) -> Binding<Bool> {
        Binding {
            shortcut.modifiers.contains(modifier)
        } set: { isEnabled in
            if isEnabled {
                shortcut.modifiers.insert(modifier)
            } else {
                shortcut.modifiers.remove(modifier)
            }
        }
    }
}

private struct ShortcutRowView: View {
    let title: String
    let shortcut: ShortcutDefinition

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut.displayText)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct ComplianceRowView: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

#Preview {
    ContentView()
        .environment(VoiceFlowModel())
}
