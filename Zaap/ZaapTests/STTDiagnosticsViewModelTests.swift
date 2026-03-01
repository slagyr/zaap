import XCTest
@testable import Zaap

@MainActor
final class STTDiagnosticsViewModelTests: XCTestCase {

    var viewModel: STTDiagnosticsViewModel!

    override func setUp() {
        super.setUp()
        viewModel = STTDiagnosticsViewModel()
    }

    // MARK: - Initial State

    func testInitialStateIsInactive() {
        XCTAssertFalse(viewModel.isActive)
    }

    func testInitialLogIsEmpty() {
        XCTAssertTrue(viewModel.logEntries.isEmpty)
    }

    func testInitialRecognitionStatusIsIdle() {
        XCTAssertEqual(viewModel.recognitionStatus, .idle)
    }

    func testInitialPartialTranscriptIsEmpty() {
        XCTAssertEqual(viewModel.partialTranscript, "")
    }

    func testInitialSilenceTimerValueIsNil() {
        XCTAssertNil(viewModel.silenceTimerElapsed)
    }

    // MARK: - Activation

    func testActivateSetsIsActiveTrue() {
        viewModel.activate()
        XCTAssertTrue(viewModel.isActive)
    }

    func testDeactivateSetsIsActiveFalse() {
        viewModel.activate()
        viewModel.deactivate()
        XCTAssertFalse(viewModel.isActive)
    }

    func testDeactivateClearsState() {
        viewModel.activate()
        viewModel.updateRecognitionStatus(.listening)
        viewModel.updatePartialTranscript("test")
        viewModel.updateSilenceTimer(0.5)
        viewModel.deactivate()

        XCTAssertEqual(viewModel.recognitionStatus, .idle)
        XCTAssertEqual(viewModel.partialTranscript, "")
        XCTAssertNil(viewModel.silenceTimerElapsed)
    }

    func testDeactivatePreservesLogEntries() {
        viewModel.activate()
        viewModel.appendLog(.partialTranscript("hello"))
        viewModel.deactivate()

        XCTAssertEqual(viewModel.logEntries.count, 1)
    }

    // MARK: - Log Entries

    func testAppendLogAddsEntry() {
        viewModel.appendLog(.partialTranscript("hello"))
        XCTAssertEqual(viewModel.logEntries.count, 1)
    }

    func testAppendLogPreservesOrder() {
        viewModel.appendLog(.partialTranscript("first"))
        viewModel.appendLog(.utteranceEmitted("second"))
        viewModel.appendLog(.silenceThresholdHit(elapsed: 1.5))

        XCTAssertEqual(viewModel.logEntries.count, 3)
        if case .partialTranscript(let text) = viewModel.logEntries[0].event {
            XCTAssertEqual(text, "first")
        } else {
            XCTFail("Expected partialTranscript")
        }
    }

    func testClearLogRemovesAllEntries() {
        viewModel.appendLog(.partialTranscript("test"))
        viewModel.appendLog(.utteranceEmitted("test"))
        viewModel.clearLog()

        XCTAssertTrue(viewModel.logEntries.isEmpty)
    }

    func testLogEntryHasTimestamp() {
        let before = Date()
        viewModel.appendLog(.partialTranscript("test"))
        let after = Date()

        let entry = viewModel.logEntries[0]
        XCTAssertTrue(entry.timestamp >= before)
        XCTAssertTrue(entry.timestamp <= after)
    }

    // MARK: - Log Event Types

    func testLogEventPartialTranscript() {
        viewModel.appendLog(.partialTranscript("hello world"))
        if case .partialTranscript(let text) = viewModel.logEntries[0].event {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("Expected partialTranscript event")
        }
    }

    func testLogEventUtteranceEmitted() {
        viewModel.appendLog(.utteranceEmitted("complete sentence"))
        if case .utteranceEmitted(let text) = viewModel.logEntries[0].event {
            XCTAssertEqual(text, "complete sentence")
        } else {
            XCTFail("Expected utteranceEmitted event")
        }
    }

    func testLogEventSilenceThresholdHit() {
        viewModel.appendLog(.silenceThresholdHit(elapsed: 1.5))
        if case .silenceThresholdHit(let elapsed) = viewModel.logEntries[0].event {
            XCTAssertEqual(elapsed, 1.5)
        } else {
            XCTFail("Expected silenceThresholdHit event")
        }
    }

    func testLogEventRecognitionStarted() {
        viewModel.appendLog(.recognitionStarted)
        if case .recognitionStarted = viewModel.logEntries[0].event {
            // pass
        } else {
            XCTFail("Expected recognitionStarted event")
        }
    }

    func testLogEventRecognitionStopped() {
        viewModel.appendLog(.recognitionStopped)
        if case .recognitionStopped = viewModel.logEntries[0].event {
            // pass
        } else {
            XCTFail("Expected recognitionStopped event")
        }
    }

    func testLogEventRecognitionError() {
        viewModel.appendLog(.recognitionError("some error"))
        if case .recognitionError(let msg) = viewModel.logEntries[0].event {
            XCTAssertEqual(msg, "some error")
        } else {
            XCTFail("Expected recognitionError event")
        }
    }

    func testLogEventSilenceTimerReset() {
        viewModel.appendLog(.silenceTimerReset)
        if case .silenceTimerReset = viewModel.logEntries[0].event {
            // pass
        } else {
            XCTFail("Expected silenceTimerReset event")
        }
    }

    func testLogEventTranscriptTooShort() {
        viewModel.appendLog(.transcriptTooShort(length: 2))
        if case .transcriptTooShort(let length) = viewModel.logEntries[0].event {
            XCTAssertEqual(length, 2)
        } else {
            XCTFail("Expected transcriptTooShort event")
        }
    }

    // MARK: - State Updates

    func testUpdateRecognitionStatus() {
        viewModel.updateRecognitionStatus(.listening)
        XCTAssertEqual(viewModel.recognitionStatus, .listening)

        viewModel.updateRecognitionStatus(.recognizing)
        XCTAssertEqual(viewModel.recognitionStatus, .recognizing)
    }

    func testUpdatePartialTranscript() {
        viewModel.updatePartialTranscript("hello")
        XCTAssertEqual(viewModel.partialTranscript, "hello")
    }

    func testUpdateSilenceTimer() {
        viewModel.updateSilenceTimer(0.75)
        XCTAssertEqual(viewModel.silenceTimerElapsed, 0.75)
    }

    func testClearSilenceTimer() {
        viewModel.updateSilenceTimer(0.5)
        viewModel.clearSilenceTimer()
        XCTAssertNil(viewModel.silenceTimerElapsed)
    }

    // MARK: - Log Size Limit

    func testLogEntriesLimitedTo500() {
        for i in 0..<600 {
            viewModel.appendLog(.partialTranscript("entry \(i)"))
        }

        XCTAssertEqual(viewModel.logEntries.count, 500)
        // Should keep the most recent entries
        if case .partialTranscript(let text) = viewModel.logEntries.last!.event {
            XCTAssertEqual(text, "entry 599")
        } else {
            XCTFail("Expected last entry to be entry 599")
        }
    }
}
