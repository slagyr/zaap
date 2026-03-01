import XCTest
import AVFoundation
@testable import Zaap

@MainActor
final class TTSDiagnosticsCoordinatorTests: XCTestCase {

    var synthesizer: MockTTSDiagSynthesizer!
    var viewModel: TTSDiagnosticsViewModel!
    var coordinator: TTSDiagnosticsCoordinator!

    override func setUp() {
        super.setUp()
        synthesizer = MockTTSDiagSynthesizer()
        viewModel = TTSDiagnosticsViewModel()
        coordinator = TTSDiagnosticsCoordinator(
            viewModel: viewModel,
            synthesizer: synthesizer
        )
    }

    // MARK: - Open

    func testOpenActivatesViewModel() {
        coordinator.open()
        XCTAssertTrue(viewModel.isActive)
    }

    func testOpenDoesNotStartPlaying() {
        coordinator.open()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testOpenDoesNotCallSynthesizer() {
        coordinator.open()
        XCTAssertFalse(synthesizer.speakCalled)
    }

    // MARK: - Close

    func testCloseDeactivatesViewModel() {
        coordinator.open()
        coordinator.close()
        XCTAssertFalse(viewModel.isActive)
    }

    func testCloseStopsPlaybackIfPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.close()
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(synthesizer.stopCalled)
    }

    func testCloseResetsAudioLevel() {
        coordinator.open()
        coordinator.play()
        viewModel.updateAudioLevel(0.5)
        coordinator.close()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    // MARK: - Play

    func testPlaySetsViewModelPlaying() {
        coordinator.open()
        coordinator.play()
        XCTAssertTrue(viewModel.isPlaying)
    }

    func testPlayCallsSynthesizerSpeak() {
        coordinator.open()
        coordinator.play()
        XCTAssertTrue(synthesizer.speakCalled)
    }

    func testPlaySpeaksTheRavenText() {
        coordinator.open()
        coordinator.play()
        XCTAssertTrue(synthesizer.lastUtteranceText?.contains("Once upon a midnight dreary") ?? false)
    }

    func testPlayWhileAlreadyPlayingDoesNothing() {
        coordinator.open()
        coordinator.play()
        synthesizer.speakCalled = false
        coordinator.play()
        XCTAssertFalse(synthesizer.speakCalled)
    }

    func testPlaySetsSynthesizerDelegate() {
        coordinator.open()
        coordinator.play()
        XCTAssertNotNil(synthesizer.delegate)
    }

    // MARK: - Pause

    func testPauseSetsViewModelNotPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testPauseStopsSynthesizer() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        XCTAssertTrue(synthesizer.stopCalled)
    }

    func testPauseWhileNotPlayingDoesNothing() {
        coordinator.pause()
        XCTAssertFalse(synthesizer.stopCalled)
    }

    // MARK: - Stop (keeps panel open)

    func testStopSetsNotPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.stop()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testStopStopsSynthesizer() {
        coordinator.open()
        coordinator.play()
        coordinator.stop()
        XCTAssertTrue(synthesizer.stopCalled)
    }

    func testStopKeepsPanelActive() {
        coordinator.open()
        coordinator.play()
        coordinator.stop()
        XCTAssertTrue(viewModel.isActive)
    }

    func testStopResetsAudioLevel() {
        coordinator.open()
        coordinator.play()
        viewModel.updateAudioLevel(0.5)
        coordinator.stop()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    // MARK: - Toggle

    func testTogglePlaysWhenNotPlaying() {
        coordinator.open()
        coordinator.toggle()
        XCTAssertTrue(viewModel.isPlaying)
    }

    func testTogglePausesWhenPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.toggle()
        XCTAssertFalse(viewModel.isPlaying)
    }

    // MARK: - Word Highlighting Delegate

    func testWillSpeakRangeUpdatesHighlight() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 5, length: 4))
        XCTAssertEqual(viewModel.highlightRange, NSRange(location: 5, length: 4))
    }

    // MARK: - Finished Speaking

    func testDidFinishSetsNotPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateDidFinish()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testDidFinishClearsHighlight() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 3))
        coordinator.simulateDidFinish()
        XCTAssertNil(viewModel.highlightRange)
    }

    // MARK: - Audio Level

    func testUpdateAudioLevelForwardsToViewModel() {
        coordinator.open()
        coordinator.play()
        coordinator.updateAudioLevel(0.75)
        XCTAssertEqual(viewModel.audioLevel, 0.75)
    }
}

// MARK: - Mock Synthesizer for TTS Diagnostics

final class MockTTSDiagSynthesizer: SpeechSynthesizing {
    var delegate: (any AVSpeechSynthesizerDelegate)?
    var isSpeaking = false
    var speakCalled = false
    var stopCalled = false
    var lastUtteranceText: String?

    func speak(_ utterance: AVSpeechUtterance) {
        speakCalled = true
        isSpeaking = true
        lastUtteranceText = utterance.speechString
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCalled = true
        isSpeaking = false
        return true
    }
}
