import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class VoiceFlowModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var hasCompletedStartupGuide = UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedStartupGuide)
    @Published var transcript = ""
    @Published var latestNotice = "Ready"
    @Published var startShortcut: ShortcutDefinition {
        didSet {
            startShortcut.save(to: DefaultsKey.startShortcut)
            registerShortcuts()
        }
    }
    @Published var stopShortcut: ShortcutDefinition {
        didSet {
            stopShortcut.save(to: DefaultsKey.stopShortcut)
            registerShortcuts()
        }
    }

    let modelBundle = WhisperModelBundle()

    private let recorder = AudioRecorder()
    private let transcriber = WhisperTranscriptionService()
    private let hotKeyCenter = HotKeyCenter()
    private var recordingURL: URL?

    init() {
        startShortcut = ShortcutDefinition.load(from: DefaultsKey.startShortcut) ?? .defaultStart
        stopShortcut = ShortcutDefinition.load(from: DefaultsKey.stopShortcut) ?? .defaultStop
        registerShortcuts()
    }

    deinit {
        hotKeyCenter.unregisterAll()
    }

    var status: AppStatus {
        if isRecording { return .recording }
        if isProcessing { return .processing }
        if !modelBundle.isAvailable { return .modelMissing }
        return .ready
    }

    func completeStartupGuide() {
        hasCompletedStartupGuide = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasCompletedStartupGuide)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        Task {
            do {
                latestNotice = "Requesting microphone access"
                try await recorder.requestPermission()
                let url = try recorder.start()
                recordingURL = url
                isRecording = true
                latestNotice = "Recording"
            } catch {
                latestNotice = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        do {
            let url = try recorder.stop()
            isRecording = false
            isProcessing = true
            latestNotice = "Transcribing locally"
            transcribe(url)
        } catch {
            isRecording = false
            latestNotice = error.localizedDescription
        }
    }

    func resetTranscript() {
        transcript = ""
        latestNotice = "Transcript cleared"
    }

    private func transcribe(_ url: URL) {
        Task {
            do {
                let text = try await transcriber.transcribe(audioURL: url, modelBundle: modelBundle)
                transcript = text
                latestNotice = text.isEmpty ? "No speech detected" : "Transcript ready"
            } catch {
                latestNotice = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func registerShortcuts() {
        hotKeyCenter.unregisterAll()
        hotKeyCenter.register(startShortcut) { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotKeyCenter.register(stopShortcut) { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
    }
}

enum AppStatus {
    case ready
    case recording
    case processing
    case modelMissing

    var title: String {
        switch self {
        case .ready: "Ready"
        case .recording: "Recording"
        case .processing: "Transcribing"
        case .modelMissing: "Model setup needed"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "waveform"
        case .recording: "mic.fill"
        case .processing: "sparkles"
        case .modelMissing: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready: .green
        case .recording: .red
        case .processing: .blue
        case .modelMissing: .orange
        }
    }
}

private enum DefaultsKey {
    static let hasCompletedStartupGuide = "hasCompletedStartupGuide"
    static let startShortcut = "startShortcut"
    static let stopShortcut = "stopShortcut"
}

struct WhisperModelBundle {
    private let folderName = "whisper-tiny.en"

    var modelDirectory: URL? {
        Bundle.main.url(forResource: folderName, withExtension: nil)
    }

    var isAvailable: Bool {
        guard let modelDirectory else { return false }
        let requiredFiles = ["config.json", "tokenizer.json", "preprocessor_config.json"]
        return requiredFiles.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent(fileName).path)
        }
    }

    var displayPath: String {
        modelDirectory?.path ?? "Bundle Resources/whisper-tiny.en"
    }
}

final class WhisperTranscriptionService {
    func transcribe(audioURL: URL, modelBundle: WhisperModelBundle) async throws -> String {
        guard modelBundle.isAvailable else {
            throw VoiceFlowError.modelMissing
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let byteCount = attributes[.size] as? Int64 ?? 0
        guard byteCount > 0 else {
            throw VoiceFlowError.emptyRecording
        }

        throw VoiceFlowError.runtimeNotConfigured
    }
}

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?

    func requestPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw VoiceFlowError.microphoneDenied }
        case .denied, .restricted:
            throw VoiceFlowError.microphoneDenied
        @unknown default:
            throw VoiceFlowError.microphoneDenied
        }
    }

    func start() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceFlow", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recording-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw VoiceFlowError.recordingFailed
        }
        self.recorder = recorder
        return url
    }

    func stop() throws -> URL {
        guard let recorder else { throw VoiceFlowError.noActiveRecording }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        return url
    }
}

enum VoiceFlowError: LocalizedError {
    case microphoneDenied
    case recordingFailed
    case noActiveRecording
    case emptyRecording
    case modelMissing
    case runtimeNotConfigured

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone."
        case .recordingFailed:
            "VoiceFlow could not start recording from the selected microphone."
        case .noActiveRecording:
            "There is no active recording to stop."
        case .emptyRecording:
            "The recording did not contain audio data."
        case .modelMissing:
            "Bundle the openai/whisper-tiny.en files in Resources/whisper-tiny.en before enabling local transcription."
        case .runtimeNotConfigured:
            "The Whisper runtime is not connected yet. Add a Core ML, whisper.cpp, or WhisperKit backend behind WhisperTranscriptionService."
        }
    }
}
