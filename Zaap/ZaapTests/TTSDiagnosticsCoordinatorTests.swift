import XCTest
import AVFoundation
@testable import Zaap

@MainActor
final class TTSDiagnosticsCoordinatorTests: XCTestCase {

    var mockSynthesizer: MockBufferSynthesizer!
    var mockPlayerNode: MockAudioPlayerNode!
    var mockEngine: MockPlaybackEngine!
    var player: TTSAudioPlayer!
    var viewModel: TTSDiagnosticsViewModel!
    var coordinator: TTSDiagnosticsCoordinator!

    override func setUp() {
        super.setUp()
        mockSynthesizer = MockBufferSynthesizer()
        mockPlayerNode = MockAudioPlayerNode()
        mockEngine = MockPlaybackEngine()
        player = TTSAudioPlayer(
            synthesizer: mockSynthesizer,
            playerNode: mockPlayerNode,
            engine: mockEngine
        )
        viewModel = TTSDiagnosticsViewModel()
        coordinator = TTSDiagnosticsCoordinator(
            viewModel: viewModel,
            player: player
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

    func testOpenDoesNotCallPlayer() {
        coordinator.open()
        XCTAssertFalse(mockSynthesizer.writeCalled)
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
        XCTAssertTrue(mockPlayerNode.stopCalled)
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

    func testPlayCallsPlayerPlay() {
        coordinator.open()
        coordinator.play()
        XCTAssertTrue(mockSynthesizer.writeCalled)
    }

    func testPlaySpeaksTheRavenText() {
        coordinator.open()
        coordinator.play()
        XCTAssertTrue(mockSynthesizer.lastUtteranceText?.contains("Once upon a midnight dreary") ?? false)
    }

    func testPlayWhileAlreadyPlayingDoesNothing() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.writeCalled = false
        coordinator.play()
        XCTAssertFalse(mockSynthesizer.writeCalled)
    }

    // MARK: - Pause

    func testPauseSetsViewModelNotPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testPausePausesPlayerNode() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        XCTAssertTrue(mockPlayerNode.pauseCalled)
    }

    func testPauseWhileNotPlayingDoesNothing() {
        coordinator.pause()
        XCTAssertFalse(mockPlayerNode.pauseCalled)
    }

    // MARK: - Resume after Pause

    func testPlayAfterPauseResumesPlayer() {
        coordinator.open()
        coordinator.play()
        coordinator.pause()
        mockSynthesizer.writeCalled = false
        mockPlayerNode.playCalled = false
        coordinator.play()
        XCTAssertTrue(mockPlayerNode.playCalled, "Should resume the player node")
        XCTAssertFalse(mockSynthesizer.writeCalled, "Should not start a new synthesis")
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

    func testStopStopsPlayer() {
        coordinator.open()
        coordinator.play()
        coordinator.stop()
        XCTAssertTrue(mockPlayerNode.stopCalled)
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

    // MARK: - Word Highlighting via Callback

    func testWordBoundaryCallbackUpdatesHighlight() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 5, length: 4))
        XCTAssertEqual(viewModel.highlightRange, NSRange(location: 5, length: 4))
    }

    // MARK: - Finished Speaking

    func testFinishCallbackSetsNotPlaying() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateFinish()
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testFinishCallbackClearsHighlight() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 3))
        mockSynthesizer.simulateFinish()
        XCTAssertNil(viewModel.highlightRange)
    }

    // MARK: - Audio Level Pulsing

    func testWordBoundaryPulsesAudioLevel() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 4))
        XCTAssertGreaterThan(viewModel.audioLevel, 0.0)
    }

    func testAudioLevelPeakIsAtMostOne() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 4))
        XCTAssertLessThanOrEqual(viewModel.audioLevel, 1.0)
    }

    func testFinishResetsAudioLevel() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 4))
        mockSynthesizer.simulateFinish()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    func testStopResetsAudioLevelAfterPulse() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 4))
        coordinator.stop()
        XCTAssertEqual(viewModel.audioLevel, 0.0)
    }

    func testMultipleWordsPulseAudioLevel() {
        coordinator.open()
        coordinator.play()
        mockSynthesizer.simulateMarker(at: NSRange(location: 0, length: 4))
        let firstLevel = viewModel.audioLevel
        mockSynthesizer.simulateMarker(at: NSRange(location: 5, length: 4))
        let secondLevel = viewModel.audioLevel
        XCTAssertGreaterThan(firstLevel, 0.0)
        XCTAssertGreaterThan(secondLevel, 0.0)
    }

    // MARK: - Simulate helpers still work

    func testSimulateWillSpeakRangeUpdatesHighlight() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateWillSpeakRange(NSRange(location: 5, length: 4))
        XCTAssertEqual(viewModel.highlightRange, NSRange(location: 5, length: 4))
    }

    func testSimulateDidFinishSetsNotPlaying() {
        coordinator.open()
        coordinator.play()
        coordinator.simulateDidFinish()
        XCTAssertFalse(viewModel.isPlaying)
    }
}
