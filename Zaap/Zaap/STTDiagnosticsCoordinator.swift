import Foundation

/// Wires VoiceEngine events to STTDiagnosticsViewModel in dry-run mode.
/// Mic is live but no transcripts are sent to the gateway.
@MainActor
final class STTDiagnosticsCoordinator: ObservableObject {
    let diagnosticsViewModel: STTDiagnosticsViewModel
    private let voiceEngine: VoiceEngineProtocol
    @Published private(set) var isRunning = false

    init(diagnosticsViewModel: STTDiagnosticsViewModel,
         voiceEngine: VoiceEngineProtocol) {
        self.diagnosticsViewModel = diagnosticsViewModel
        self.voiceEngine = voiceEngine
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        diagnosticsViewModel.activate()
        diagnosticsViewModel.appendLog(.recognitionStarted)
        diagnosticsViewModel.updateRecognitionStatus(.listening)

        voiceEngine.onPartialTranscript = { [weak self] text in
            self?.diagnosticsViewModel.updatePartialTranscript(text)
            self?.diagnosticsViewModel.updateRecognitionStatus(.recognizing)
            self?.diagnosticsViewModel.appendLog(.partialTranscript(text))
            self?.diagnosticsViewModel.clearSilenceTimer()
        }

        voiceEngine.onUtteranceComplete = { [weak self] text in
            self?.diagnosticsViewModel.appendLog(.silenceThresholdHit(elapsed: 0))
            self?.diagnosticsViewModel.appendLog(.utteranceEmitted(text))
            self?.diagnosticsViewModel.updatePartialTranscript("")
            self?.diagnosticsViewModel.clearSilenceTimer()
            self?.diagnosticsViewModel.updateRecognitionStatus(.listening)
        }

        voiceEngine.onError = { [weak self] error in
            let message: String
            switch error {
            case .notAuthorized: message = "Not authorized"
            case .recognizerUnavailable: message = "Recognizer unavailable"
            case .recognitionFailed(let msg): message = "Recognition failed: \(msg)"
            case .audioSessionFailed(let msg): message = "Audio session failed: \(msg)"
            }
            self?.diagnosticsViewModel.appendLog(.recognitionError(message))
            self?.diagnosticsViewModel.updateRecognitionStatus(.idle)
        }

        voiceEngine.startListening()
    }

    func stop() {
        guard isRunning else { return }
        voiceEngine.stopListening()
        voiceEngine.onPartialTranscript = nil
        voiceEngine.onUtteranceComplete = nil
        voiceEngine.onError = nil
        diagnosticsViewModel.appendLog(.recognitionStopped)
        diagnosticsViewModel.updateRecognitionStatus(.idle)
        diagnosticsViewModel.deactivate()
        isRunning = false
    }
}
