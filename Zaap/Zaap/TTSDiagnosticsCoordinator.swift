import AVFoundation

/// Drives TTS diagnostics: speaks The Raven text with real-time word highlighting
/// and audio level metering via AVSpeechSynthesizerDelegate.
@MainActor
final class TTSDiagnosticsCoordinator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    let viewModel: TTSDiagnosticsViewModel
    private let synthesizer: SpeechSynthesizing

    init(viewModel: TTSDiagnosticsViewModel,
         synthesizer: SpeechSynthesizing) {
        self.viewModel = viewModel
        self.synthesizer = synthesizer
        super.init()
    }

    func play() {
        guard !viewModel.isPlaying else { return }
        viewModel.activate()
        viewModel.setPlaying(true)
        synthesizer.delegate = self

        let utterance = AVSpeechUtterance(string: viewModel.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func pause() {
        guard viewModel.isPlaying else { return }
        viewModel.setPlaying(false)
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    func stop() {
        _ = synthesizer.stopSpeaking(at: .immediate)
        viewModel.deactivate()
    }

    func toggle() {
        if viewModel.isPlaying {
            pause()
        } else {
            play()
        }
    }

    // MARK: - Testable Simulation Points

    func simulateWillSpeakRange(_ range: NSRange) {
        viewModel.updateHighlightRange(range)
    }

    func simulateDidFinish() {
        viewModel.setPlaying(false)
    }

    func updateAudioLevel(_ level: Float) {
        viewModel.updateAudioLevel(level)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.viewModel.updateHighlightRange(characterRange)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.viewModel.setPlaying(false)
        }
    }
}
