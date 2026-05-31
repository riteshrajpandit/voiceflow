import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

actor WhisperKitTranscriber {
    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    private var loadedModelFolder: String?
    #endif

    func transcribe(audioURL: URL, modelBundle: WhisperModelBundle) async throws -> String {
        #if canImport(WhisperKit)
        let whisperKit = try await loadWhisperKit(modelBundle: modelBundle)
        let results = try await whisperKit.transcribe(audioPath: audioURL.path)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw VoiceFlowError.whisperKitMissing
        #endif
    }

    #if canImport(WhisperKit)
    private func loadWhisperKit(modelBundle: WhisperModelBundle) async throws -> WhisperKit {
        let localModelFolder = modelBundle.modelDirectory?.path
        let requestedModelFolder = localModelFolder ?? "managed-download:small.en"

        if let whisperKit, loadedModelFolder == requestedModelFolder {
            return whisperKit
        }

        let config: WhisperKitConfig
        if let localModelFolder {
            config = WhisperKitConfig(
                modelFolder: localModelFolder,
                tokenizerFolder: URL(fileURLWithPath: localModelFolder),
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
        } else {
            config = WhisperKitConfig(
                model: "small.en",
                modelRepo: "argmaxinc/whisperkit-coreml",
                verbose: false,
                prewarm: true,
                load: true,
                download: true
            )
        }

        do {
            let whisperKit = try await WhisperKit(config)
            self.whisperKit = whisperKit
            loadedModelFolder = requestedModelFolder
            return whisperKit
        } catch {
            throw VoiceFlowError.runtimeNotConfigured
        }
    }
    #endif
}
