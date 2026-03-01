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

    func testPausePausesSynthesizerNotStops() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        XCTAssertTrue(synthesizer.pauseCalled)
        XCTAssertFalse(synthesizer.stopCalled)
    }

    func testPauseWhileNotPlayingDoesNothing() {
        coordinator.pause()
        XCTAssertFalse(synthesizer.pauseCalled)
    }

    // MARK: - Resume after Pause

    func testPlayAfterPauseResumesSynthesizer() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        synthesizer.speakCalled = false
        coordinator.play()
        XCTAssertTrue(synthesizer.continueCalled)
        XCTAssertFalse(synthesizer.speakCalled, "Should resume, not start a new utterance")
    }

    func testPlayAfterPauseSetsPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        coordinator.play()
        XCTAssertTrue(viewModel.isPlaying)
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

    // MARK: - Audio Level Pulsing

    func testWillSpeakRangePulsesAudioLevel() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 4))
        XCTAssertGreaterThan(viewModel.audioLevel, 0.0)
    }

    func testAudioLevelPeakIsAtMostOne() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 4))
        XCTAssertLessThanOrEqual(viewModel.audioLevel, 1.0)
    }

    func testDidFinishResetsAudioLevel() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 4))
        coordinator.simulateDidFinish()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    func testStopResetsAudioLevelAfterPulse() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 4))
        coordinator.stop()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    func testMultipleWordsPulseAudioLevel() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 0, length: 4))
        let firstLevel = viewModel.audioLevel
        coordinator.simulateWillSpeakRange(NSRange(location: 5, length: 4))
        let secondLevel = viewModel.audioLevel
        XCTAssertGreaterThan(firstLevel, 0.0)
        XCTAssertGreaterThan(secondLevel, 0.0)
    }
}

// MARK: - Mock Synthesizer for TTS Diagnostics

final class MockTTSDiagSynthesizer: SpeechSynthesizing {
    var delegate: (any AVSpeechSynthesizerDelegate)?
    var isSpeaking = false
    var isPaused = false
    var speakCalled = false
    var stopCalled = false
    var pauseCalled = false
    var continueCalled = false
    var lastUtteranceText: String?

    func speak(_ utterance: AVSpeechUtterance) {
        speakCalled = true
        isSpeaking = true
        isPaused = false
        lastUtteranceText = utterance.speechString
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCalled = true
        isSpeaking = false
        isPaused = false
        return true
    }

    func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        pauseCalled = true
        isPaused = true
        return true
    }

    func continueSpeaking() -> Bool {
        continueCalled = true
        isPaused = false
        return true
    }
}
