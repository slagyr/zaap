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

    // MARK: - Play

    func testPlayActivatesViewModel() {
        coordinator.play()
        XCTAssertTrue(viewModel.isActive)
    }

    func testPlaySetsViewModelPlaying() {
        coordinator.play()
        XCTAssertTrue(viewModel.isPlaying)
    }

    func testPlayCallsSynthesizerSpeak() {
        coordinator.play()
        XCTAssertTrue(synthesizer.speakCalled)
    }

    func testPlaySpeaksTheRavenText() {
        coordinator.play()
        XCTAssertTrue(synthesizer.lastUtteranceText?.contains("Once upon a midnight dreary") ?? false)
    }

    func testPlayWhileAlreadyPlayingDoesNothing() {
        coordinator.play()
        synthesizer.speakCalled = false
        coordinator.play()
        XCTAssertFalse(synthesizer.speakCalled)
    }

    func testPlaySetsSynthesizerDelegate() {
        coordinator.play()
        XCTAssertNotNil(synthesizer.delegate)
    }

    // MARK: - Pause

    func testPauseSetsViewModelNotPlaying() {
        coordinator.play()
        coordinator.pause()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testPauseStopsSynthesizer() {
        coordinator.play()
        coordinator.pause()
        XCTAssertTrue(synthesizer.stopCalled)
    }

    func testPauseWhileNotPlayingDoesNothing() {
        coordinator.pause()
        XCTAssertFalse(synthesizer.stopCalled)
    }

    // MARK: - Stop

    func testStopDeactivatesViewModel() {
        coordinator.play()
        coordinator.stop()
        XCTAssertFalse(viewModel.isActive)
    }

    func testStopSetsNotPlaying() {
        coordinator.play()
        coordinator.stop()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testStopStopsSynthesizer() {
        coordinator.play()
        coordinator.stop()
        XCTAssertTrue(synthesizer.stopCalled)
    }

    func testStopResetsAudioLevel() {
        coordinator.play()
        viewModel.updateAudioLevel(0.5)
        coordinator.stop()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    // MARK: - Toggle

    func testTogglePlaysWhenNotPlaying() {
        coordinator.toggle()
        XCTAssertTrue(viewModel.isPlaying)
    }

    func testTogglePausesWhenPlaying() {
        coordinator.play()
        coordinator.toggle()
        XCTAssertFalse(viewModel.isPlaying)
    }

    // MARK: - Word Highlighting Delegate

    func testWillSpeakRangeUpdatesHighlight() {
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 5, length: 4))
        XCTAssertEqual(viewModel.highlightRange, NSRange(location: 5, length: 4))
    }

    // MARK: - Finished Speaking

    func testDidFinishSetsNotPlaying() {
        coordinator.play()
        coordinator.simulateDidFinish()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testDidFinishClearsHighlight() {
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 3))
        coordinator.simulateDidFinish()
        XCTAssertNil(viewModel.highlightRange)
    }

    // MARK: - Audio Level

    func testUpdateAudioLevelForwardsToViewModel() {
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
