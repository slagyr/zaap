import XCTest
import AVFoundation
@testable import Zaap

@MainActor
final class DualDiagnosticsPanelTests: XCTestCase {

    var sttVoiceEngine: MockVoiceEngine!
    var sttViewModel: STTDiagnosticsViewModel!
    var sttCoordinator: STTDiagnosticsCoordinator!

    var ttsSynthesizer: MockTTSDiagSynthesizer!
    var ttsViewModel: TTSDiagnosticsViewModel!
    var ttsCoordinator: TTSDiagnosticsCoordinator!

    override func setUp() {
        super.setUp()
        sttVoiceEngine = MockVoiceEngine()
        sttViewModel = STTDiagnosticsViewModel()
        sttCoordinator = STTDiagnosticsCoordinator(
            diagnosticsViewModel: sttViewModel,
            voiceEngine: sttVoiceEngine
        )

        ttsSynthesizer = MockTTSDiagSynthesizer()
        ttsViewModel = TTSDiagnosticsViewModel()
        ttsCoordinator = TTSDiagnosticsCoordinator(
            viewModel: ttsViewModel,
            synthesizer: ttsSynthesizer
        )
    }

    // MARK: - Both Panels Active Simultaneously

    func testBothPanelsCanBeActiveSimultaneously() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()

        XCTAssertTrue(sttViewModel.isActive)
        XCTAssertTrue(ttsViewModel.isActive)
    }

    func testSTTReceivesTranscriptsWhileTTSIsPlaying() {
        ttsCoordinator.open()
        ttsCoordinator.play()
        sttCoordinator.start()

        sttVoiceEngine.onPartialTranscript?("Once upon")
        XCTAssertEqual(sttViewModel.partialTranscript, "Once upon")
        XCTAssertTrue(ttsViewModel.isPlaying)
    }

    func testTTSHighlightsWordsWhileSTTIsListening() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()

        ttsCoordinator.simulateWillSpeakRange(NSRange(location: 0, length: 4))
        XCTAssertEqual(ttsViewModel.highlightRange, NSRange(location: 0, length: 4))
        XCTAssertTrue(sttCoordinator.isRunning)
    }

    // MARK: - Stopping One Panel Does Not Affect the Other

    func testStoppingSTTDoesNotAffectTTS() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()

        sttCoordinator.stop()

        XCTAssertFalse(sttViewModel.isActive)
        XCTAssertTrue(ttsViewModel.isActive)
        XCTAssertTrue(ttsViewModel.isPlaying)
    }

    func testClosingTTSDoesNotAffectSTT() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()

        ttsCoordinator.close()

        XCTAssertTrue(sttViewModel.isActive)
        XCTAssertTrue(sttCoordinator.isRunning)
        XCTAssertFalse(ttsViewModel.isActive)
    }

    func testSTTContinuesReceivingAfterTTSCloses() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()
        ttsCoordinator.close()

        sttVoiceEngine.onPartialTranscript?("still listening")
        XCTAssertEqual(sttViewModel.partialTranscript, "still listening")
    }

    func testTTSContinuesPlayingAfterSTTStops() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()
        sttCoordinator.stop()

        ttsCoordinator.simulateWillSpeakRange(NSRange(location: 5, length: 4))
        XCTAssertEqual(ttsViewModel.highlightRange, NSRange(location: 5, length: 4))
        XCTAssertTrue(ttsViewModel.isPlaying)
    }

    // MARK: - Independent Audio Level Updates

    func testTTSAudioLevelUpdatesWhileSTTActive() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()

        ttsCoordinator.updateAudioLevel(0.6)
        XCTAssertEqual(ttsViewModel.audioLevel, 0.6)
    }

    // MARK: - Restart After Both Closed

    func testBothCanRestartAfterBeingClosed() {
        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()
        sttCoordinator.stop()
        ttsCoordinator.close()

        XCTAssertFalse(sttViewModel.isActive)
        XCTAssertFalse(ttsViewModel.isActive)

        sttCoordinator.start()
        ttsCoordinator.open()
        ttsCoordinator.play()

        XCTAssertTrue(sttViewModel.isActive)
        XCTAssertTrue(ttsViewModel.isActive)
    }
}
