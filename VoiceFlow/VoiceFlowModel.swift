import AppKit
import AVFoundation
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class VoiceFlowModel {
    var isRecording = false
    var isProcessing = false
    var isAccessibilityTrusted = false
    var hasCompletedStartupGuide = UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedStartupGuide)
    var transcript = ""
    var latestNotice = "Ready"
    var startShortcut: ShortcutDefinition {
        didSet {
            startShortcut.save(to: DefaultsKey.startShortcut)
            registerShortcuts()
        }
    }
    var stopShortcut: ShortcutDefinition {
        didSet {
            stopShortcut.save(to: DefaultsKey.stopShortcut)
            registerShortcuts()
        }
    }

    let modelBundle = WhisperModelBundle()

    private let recorder = AudioRecorder()
    private let transcriber = WhisperTranscriptionService()
    private let textInserter = TextInsertionService()
    private let hotKeyCenter = HotKeyCenter()
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    private var recordingURL: URL?
    private var shouldInsertTranscription = false
    private var insertionTargetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?

    init() {
        startShortcut = ShortcutDefinition.load(from: DefaultsKey.startShortcut) ?? .defaultStart
        stopShortcut = ShortcutDefinition.load(from: DefaultsKey.stopShortcut) ?? .defaultStop
        refreshAccessibilityStatus()
        updateLastExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.updateLastExternalApplication(application)
            }
        }
        registerShortcuts()
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

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = textInserter.isAccessibilityTrusted
    }

    func requestAccessibilityPermission() {
        if textInserter.requestAccessibilityPermission() {
            latestNotice = "Accessibility permission granted"
        } else {
            latestNotice = "Approve VoiceFlow in System Settings > Privacy & Security > Accessibility"
        }
        refreshAccessibilityStatus()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startSystemWideRecording()
        }
    }

    func startSystemWideRecording() {
        startRecording(shouldInsertResult: true)
    }

    func startRecording(shouldInsertResult: Bool = false) {
        guard !isRecording else { return }

        Task {
            do {
                latestNotice = "Requesting microphone access"
                try await recorder.requestPermission()
                refreshAccessibilityStatus()
                shouldInsertTranscription = shouldInsertResult
                insertionTargetApplication = shouldInsertResult ? preferredInsertionTarget() : nil
                let url = try recorder.start()
                recordingURL = url
                isRecording = true
                latestNotice = shouldInsertResult ? "Recording for focused app" : "Recording"
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
            shouldInsertTranscription = false
            insertionTargetApplication = nil
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
                if shouldInsertTranscription, !text.isEmpty {
                    try textInserter.insert(text, into: insertionTargetApplication)
                    latestNotice = "Inserted transcript into focused app"
                } else {
                    latestNotice = text.isEmpty ? "No speech detected" : "Transcript ready"
                }
                shouldInsertTranscription = false
                insertionTargetApplication = nil
            } catch {
                latestNotice = error.localizedDescription
            }
            if !isRecording {
                shouldInsertTranscription = false
                insertionTargetApplication = nil
            }
            isProcessing = false
        }
    }

    private func preferredInsertionTarget() -> NSRunningApplication? {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if isExternalApplication(frontmostApplication) {
            return frontmostApplication
        }
        return lastExternalApplication
    }

    private func updateLastExternalApplication(_ application: NSRunningApplication?) {
        guard isExternalApplication(application) else { return }
        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        return application.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    private func registerShortcuts() {
        hotKeyCenter.unregisterAll()
        hotKeyCenter.register(startShortcut) { [weak self] in
            Task { @MainActor in self?.startSystemWideRecording() }
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
    let modelName = "openai_whisper-small.en"
    let subdirectory = "Models"

    nonisolated var modelDirectory: URL? {
        Bundle.main.url(forResource: modelName, withExtension: nil, subdirectory: subdirectory)
    }

    nonisolated var isAvailable: Bool {
        guard let modelDirectory else { return false }
        let requiredEntries = [
            "AudioEncoder.mlmodelc",
            "TextDecoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "config.json",
            "generation_config.json",
            "tokenizer.json",
            "tokenizer_config.json"
        ]
        return requiredEntries.allSatisfy { entry in
            FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent(entry).path)
        }
    }

    nonisolated var displayPath: String {
        modelDirectory?.path ?? "Bundle Resources/Models/\(modelName)"
    }
}

final class WhisperTranscriptionService {
    private let whisperKitTranscriber = WhisperKitTranscriber()

    func transcribe(audioURL: URL, modelBundle: WhisperModelBundle) async throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let byteCount = attributes[.size] as? Int64 ?? 0
        guard byteCount > 0 else {
            throw VoiceFlowError.emptyRecording
        }

        return try await whisperKitTranscriber.transcribe(audioURL: audioURL, modelBundle: modelBundle)
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
    case whisperKitMissing
    case runtimeNotConfigured
    case accessibilityPermissionMissing
    case textInsertionFailed

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
            "Bundle the WhisperKit Core ML model at Resources/Models/openai_whisper-small.en before shipping offline transcription."
        case .whisperKitMissing:
            "Add the WhisperKit package product from https://github.com/argmaxinc/argmax-oss-swift to enable local transcription."
        case .runtimeNotConfigured:
            "The Whisper runtime could not be initialized. Check that the bundled model folder is complete and compatible with WhisperKit."
        case .accessibilityPermissionMissing:
            "Approve VoiceFlow in System Settings > Privacy & Security > Accessibility so it can paste into the focused app."
        case .textInsertionFailed:
            "VoiceFlow could not insert text into the focused app."
        }
    }
}
