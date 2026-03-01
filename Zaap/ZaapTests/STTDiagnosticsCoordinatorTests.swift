import XCTest
@testable import Zaap

@MainActor
final class STTDiagnosticsCoordinatorTests: XCTestCase {

    var voiceEngine: MockVoiceEngine!
    var diagnosticsVM: STTDiagnosticsViewModel!
    var coordinator: STTDiagnosticsCoordinator!

    override func setUp() {
        super.setUp()
        voiceEngine = MockVoiceEngine()
        diagnosticsVM = STTDiagnosticsViewModel()
        coordinator = STTDiagnosticsCoordinator(
            diagnosticsViewModel: diagnosticsVM,
            voiceEngine: voiceEngine
        )
    }

    // MARK: - Start

    func testStartActivatesDiagnostics() {
        coordinator.start()
        XCTAssertTrue(diagnosticsVM.isActive)
    }

    func testStartSetsIsRunningTrue() {
        coordinator.start()
        XCTAssertTrue(coordinator.isRunning)
    }

    func testStartBeginsListening() {
        coordinator.start()
        XCTAssertTrue(voiceEngine.startListeningCalled)
    }

    func testStartLogsRecognitionStarted() {
        coordinator.start()
        let events = diagnosticsVM.logEntries.map(\.event)
        XCTAssertTrue(events.contains(.recognitionStarted))
    }

    func testStartSetsRecognitionStatusToListening() {
        coordinator.start()
        XCTAssertEqual(diagnosticsVM.recognitionStatus, .listening)
    }

    func testStartWhileAlreadyRunningDoesNothing() {
        coordinator.start()
        voiceEngine.startListeningCalled = false
        coordinator.start()
        XCTAssertFalse(voiceEngine.startListeningCalled)
    }

    // MARK: - Stop

    func testStopStopsListening() {
        coordinator.start()
        coordinator.stop()
        XCTAssertTrue(voiceEngine.stopListeningCalled)
    }

    func testStopSetsIsRunningFalse() {
        coordinator.start()
        coordinator.stop()
        XCTAssertFalse(coordinator.isRunning)
    }

    func testStopDeactivatesDiagnostics() {
        coordinator.start()
        coordinator.stop()
        XCTAssertFalse(diagnosticsVM.isActive)
    }

    func testStopLogsRecognitionStopped() {
        coordinator.start()
        coordinator.stop()
        let events = diagnosticsVM.logEntries.map(\.event)
        XCTAssertTrue(events.contains(.recognitionStopped))
    }

    func testStopSetsRecognitionStatusToIdle() {
        coordinator.start()
        coordinator.stop()
        XCTAssertEqual(diagnosticsVM.recognitionStatus, .idle)
    }

    func testStopWhileNotRunningDoesNothing() {
        coordinator.stop()
        XCTAssertFalse(voiceEngine.stopListeningCalled)
    }

    func testStopClearsCallbacks() {
        coordinator.start()
        coordinator.stop()
        XCTAssertNil(voiceEngine.onPartialTranscript)
        XCTAssertNil(voiceEngine.onUtteranceComplete)
        XCTAssertNil(voiceEngine.onError)
    }

    // MARK: - Partial Transcript Routing

    func testPartialTranscriptUpdatesViewModel() {
        coordinator.start()
        voiceEngine.onPartialTranscript?("hello")
        XCTAssertEqual(diagnosticsVM.partialTranscript, "hello")
    }

    func testPartialTranscriptLogsEvent() {
        coordinator.start()
        voiceEngine.onPartialTranscript?("hello world")
        let events = diagnosticsVM.logEntries.map(\.event)
        XCTAssertTrue(events.contains(.partialTranscript("hello world")))
    }

    func testPartialTranscriptSetsStatusToRecognizing() {
        coordinator.start()
        voiceEngine.onPartialTranscript?("hello")
        XCTAssertEqual(diagnosticsVM.recognitionStatus, .recognizing)
    }

    // MARK: - Utterance Complete Routing

    func testUtteranceCompleteLogsEmittedEvent() {
        coordinator.start()
        voiceEngine.onUtteranceComplete?("complete sentence")
        let events = diagnosticsVM.logEntries.map(\.event)
        XCTAssertTrue(events.contains(.utteranceEmitted("complete sentence")))
    }

    func testUtteranceCompleteLogsSilenceThresholdHitWithElapsed() {
        voiceEngine.silenceThreshold = 1.5
        coordinator.start()
        voiceEngine.onUtteranceComplete?("complete sentence")
        let events = diagnosticsVM.logEntries.map(\.event)
        XCTAssertTrue(events.contains(.silenceThresholdHit(elapsed: 1.5)))
    }

    func testUtteranceCompleteClearsPartialTranscript() {
        coordinator.start()
        voiceEngine.onPartialTranscript?("partial text")
        voiceEngine.onUtteranceComplete?("complete text")
        XCTAssertEqual(diagnosticsVM.partialTranscript, "")
    }

    func testUtteranceCompleteSetsStatusBackToListening() {
        coordinator.start()
        voiceEngine.onPartialTranscript?("partial")
        XCTAssertEqual(diagnosticsVM.recognitionStatus, .recognizing)
        voiceEngine.onUtteranceComplete?("complete")
        XCTAssertEqual(diagnosticsVM.recognitionStatus, .listening)
    }

    // MARK: - Dry Run: No Gateway Interaction

    func testNoGatewayDependency() {
        // The coordinator should not depend on GatewayConnecting at all.
        // This test verifies by checking the init signature accepts no gateway.
        // If this compiles, the coordinator has no gateway dependency.
        let _ = STTDiagnosticsCoordinator(
            diagnosticsViewModel: STTDiagnosticsViewModel(),
            voiceEngine: MockVoiceEngine()
        )
    }

    // MARK: - Error Routing

    func testErrorLogsRecognitionError() {
        coordinator.start()
        voiceEngine.onError?(.notAuthorized)
        let events = diagnosticsVM.logEntries.map(\.event)
        let hasError = events.contains { event in
            if case .recognitionError = event { return true }
            return false
        }
        XCTAssertTrue(hasError)
    }

    func testErrorSetsStatusToIdle() {
        coordinator.start()
        voiceEngine.onError?(.recognizerUnavailable)
        XCTAssertEqual(diagnosticsVM.recognitionStatus, .idle)
    }

    func testRecognitionFailedErrorIncludesMessage() {
        coordinator.start()
        voiceEngine.onError?(.recognitionFailed("timeout"))
        let events = diagnosticsVM.logEntries.map(\.event)
        let hasMsg = events.contains { event in
            if case .recognitionError(let msg) = event {
                return msg.contains("timeout")
            }
            return false
        }
        XCTAssertTrue(hasMsg)
    }

    func testAudioSessionFailedErrorIncludesMessage() {
        coordinator.start()
        voiceEngine.onError?(.audioSessionFailed("no input"))
        let events = diagnosticsVM.logEntries.map(\.event)
        let hasMsg = events.contains { event in
            if case .recognitionError(let msg) = event {
                return msg.contains("no input")
            }
            return false
        }
        XCTAssertTrue(hasMsg)
    }
}
