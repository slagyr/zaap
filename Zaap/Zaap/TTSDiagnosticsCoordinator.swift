import AVFoundation

/// Drives TTS diagnostics: speaks The Raven text with real-time word highlighting
/// and audio level metering, routing audio through AVAudioEngine for AEC.
@MainActor
final class TTSDiagnosticsCoordinator: ObservableObject {
    let viewModel: TTSDiagnosticsViewModel
    private let player: TTSAudioPlayer

    init(viewModel: TTSDiagnosticsViewModel,
         player: TTSAudioPlayer) {
        self.viewModel = viewModel
        self.player = player
        setupCallbacks()
    }

    private func setupCallbacks() {
        player.onWordBoundary = { [weak self] (range: NSRange) in
            self?.viewModel.updateHighlightRange(range)
            self?.pulseAudioLevel(wordLength: range.length)
        }
        player.onFinish = { [weak self] in
            self?.viewModel.setPlaying(false)
            self?.viewModel.updateAudioLevel(0.0)
        }
    }

    /// Show the panel without starting playback.
    func open() {
        viewModel.activate()
    }

    /// Stop playback and dismiss the panel.
    func close() {
        player.stop()
        viewModel.updateAudioLevel(0.0)
        viewModel.deactivate()
    }

    func play() {
        guard !viewModel.isPlaying else { return }
        viewModel.setPlaying(true)

        if player.isPaused {
            player.resume()
        } else {
            player.play(text: viewModel.text)
        }
    }

    func pause() {
        guard viewModel.isPlaying else { return }
        viewModel.setPlaying(false)
        player.pause()
    }

    /// Stop playback but keep the panel open.
    func stop() {
        player.stop()
        viewModel.setPlaying(false)
        viewModel.updateAudioLevel(0.0)
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
        pulseAudioLevel(wordLength: range.length)
    }

    func simulateDidFinish() {
        viewModel.setPlaying(false)
        viewModel.updateAudioLevel(0.0)
    }

    func updateAudioLevel(_ level: Float) {
        viewModel.updateAudioLevel(level)
    }

    // MARK: - Audio Level Pulse

    private func pulseAudioLevel(wordLength: Int) {
        let base: Float = 0.4
        let scaled = Float(min(wordLength, 10)) / 10.0 * 0.6
        viewModel.updateAudioLevel(base + scaled)
    }
}
