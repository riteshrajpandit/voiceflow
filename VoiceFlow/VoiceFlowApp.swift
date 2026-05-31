import SwiftUI

@main
struct VoiceFlowApp: App {
    @StateObject private var model = VoiceFlowModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandMenu("VoiceFlow") {
                Button("Start Recording", systemImage: "mic.fill") {
                    model.startRecording()
                }
                .keyboardShortcut(model.startShortcut.keyEquivalent, modifiers: model.startShortcut.eventModifiers)
                .disabled(model.isRecording || model.isProcessing)

                Button("Stop Recording", systemImage: "stop.fill") {
                    model.stopRecording()
                }
                .keyboardShortcut(model.stopShortcut.keyEquivalent, modifiers: model.stopShortcut.eventModifiers)
                .disabled(!model.isRecording)

                Divider()

                Button("Clear Transcript", systemImage: "trash") {
                    model.resetTranscript()
                }
                .disabled(model.transcript.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }

        MenuBarExtra("VoiceFlow", systemImage: model.status.systemImage) {
            MenuBarStatusView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusView: View {
    @EnvironmentObject private var model: VoiceFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: model.status.systemImage)
                    .font(.title2)
                    .foregroundStyle(model.status.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VoiceFlow")
                        .font(.headline)
                    Text(model.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(model.latestNotice)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                Button {
                    model.startRecording()
                } label: {
                    Label("Start", systemImage: "mic.fill")
                }
                .disabled(model.isRecording || model.isProcessing)

                Button {
                    model.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!model.isRecording)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Start: \(model.startShortcut.displayText)")
                Text("Stop: \(model.stopShortcut.displayText)")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 320)
    }
}
