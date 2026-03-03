import XCTest
@testable import Zaap

// MARK: - Test Doubles

final class MockSpeechRecognizer: SpeechRecognizing {
    var isAvailable = true
    var authorizationStatus: SpeechAuthorizationStatus = .authorized
    var recognitionTaskToReturn: MockRecognitionTask?
    var lastRequest: (any SpeechRecognitionRequesting)?
    var taskCreationCount = 0
    var allCreatedTasks: [MockRecognitionTask] = []

    func recognitionTask(with request: any SpeechRecognitionRequesting,
                         resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void) -> SpeechRecognitionTaskProtocol {
        lastRequest = request
        taskCreationCount += 1
        let task = recognitionTaskToReturn ?? MockRecognitionTask()
        task.resultHandler = resultHandler
        allCreatedTasks.append(task)
        return task
    }
}

final class MockRecognitionTask: SpeechRecognitionTaskProtocol {
    var cancelCalled = false
    var finishCalled = false
    var resultHandler: ((SpeechRecognitionResultProtocol?, Error?) -> Void)?

    func cancel() { cancelCalled = true }
    func finish() { finishCalled = true }

    func simulateResult(_ text: String, isFinal: Bool) {
        let result = MockRecognitionResult(bestTranscriptionString: text, isFinal: isFinal)
        resultHandler?(result, nil)
    }

    func simulateError(_ error: Error) {
        resultHandler?(nil, error)
    }
}

struct MockRecognitionResult: SpeechRecognitionResultProtocol {
    var bestTranscriptionString: String
    var isFinal: Bool
}

final class MockAudioEngineProvider: AudioEngineProviding {
    var isRunning = false
    var prepareCalled = false
    var startCalled = false
    var stopCalled = false
    var tapInstalled = false
    var tapRemoved = false

    func prepare() { prepareCalled = true }

    func start() throws {
        startCalled = true
        isRunning = true
    }

    func stop() {
        stopCalled = true
        isRunning = false
    }

    func installTap(onBus bus: Int, bufferSize: UInt32, format: MockAudioFormat?,
                     block: @escaping (MockAudioBuffer) -> Void) {
        tapInstalled = true
    }

    func removeTap(onBus bus: Int) {
        tapRemoved = true
    }

    func inputFormat(forBus bus: Int) -> MockAudioFormat {
        return MockAudioFormat()
    }
}

struct MockAudioFormat {}
struct MockAudioBuffer {}

final class MockAudioSessionConfigurator: AudioSessionConfiguring {
    var setCategoryCalled = false
    var setActiveCalled = false
    var shouldThrowOnConfigure = false
    var interruptionHandler: ((Bool) -> Void)?

    func configureForVoice() throws {
        setCategoryCalled = true
        if shouldThrowOnConfigure {
            throw NSError(domain: "AudioSession", code: 1, userInfo: nil)
        }
    }

    func setActive(_ active: Bool) throws {
        setActiveCalled = true
    }

    func registerInterruptionHandler(_ handler: @escaping (Bool) -> Void) {
        interruptionHandler = handler
    }
}

final class MockTimerFactory: TimerScheduling {
    var lastInterval: TimeInterval?
    var lastFireHandler: (() -> Void)?
    var invalidateCalled = false
    var allTokens: [MockTimerToken] = []

    func scheduleTimer(interval: TimeInterval, handler: @escaping () -> Void) -> TimerToken {
        lastInterval = interval
        lastFireHandler = handler
        let token = MockTimerToken()
        token.factory = self
        allTokens.append(token)
        return token
    }
}

final class MockTimerToken: TimerToken {
    weak var factory: MockTimerFactory?
    var invalidateCount = 0
    func invalidate() {
        invalidateCount += 1
        factory?.invalidateCalled = true
    }
}

// MARK: - Tests

final class VoiceEngineTests: XCTestCase {

    var engine: VoiceEngine<MockAudioEngineProvider>!
    var speechRecognizer: MockSpeechRecognizer!
    var audioEngine: MockAudioEngineProvider!
    var audioSession: MockAudioSessionConfigurator!
    var timerFactory: MockTimerFactory!
    var mockTask: MockRecognitionTask!

    @MainActor
    override func setUp() {
        super.setUp()
        speechRecognizer = MockSpeechRecognizer()
        audioEngine = MockAudioEngineProvider()
        audioSession = MockAudioSessionConfigurator()
        timerFactory = MockTimerFactory()
        mockTask = MockRecognitionTask()
        speechRecognizer.recognitionTaskToReturn = mockTask

        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5
        )
    }

    /// Helper: simulate a result and wait for the Task to execute on MainActor.
    @MainActor
    private func simulateResultAndWait(_ text: String, isFinal: Bool) async {
        mockTask.simulateResult(text, isFinal: isFinal)
        // Yield to allow the Task { @MainActor } to execute
        await Task.yield()
        // Run the run loop briefly to process
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    @MainActor
    private func simulateErrorAndWait(_ error: Error) async {
        mockTask.simulateError(error)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    // MARK: - Initial State

    @MainActor
    func testInitialState() {
        XCTAssertFalse(engine.isListening)
        XCTAssertEqual(engine.currentTranscript, "")
    }

    // MARK: - Authorization

    @MainActor
    func testStartListeningWhenNotAuthorizedReportsError() {
        speechRecognizer.authorizationStatus = .denied
        var reportedError: VoiceEngineError?
        engine.onError = { reportedError = $0 }

        engine.startListening()

        XCTAssertEqual(reportedError, .notAuthorized)
        XCTAssertFalse(engine.isListening)
    }

    @MainActor
    func testStartListeningWhenRecognizerUnavailableReportsError() {
        speechRecognizer.isAvailable = false
        var reportedError: VoiceEngineError?
        engine.onError = { reportedError = $0 }

        engine.startListening()

        XCTAssertEqual(reportedError, .recognizerUnavailable)
        XCTAssertFalse(engine.isListening)
    }

    // MARK: - Starting Listening

    @MainActor
    func testStartListeningConfiguresAudioSession() {
        engine.startListening()
        XCTAssertTrue(audioSession.setCategoryCalled)
    }

    @MainActor
    func testStartListeningStartsAudioEngine() {
        engine.startListening()
        XCTAssertTrue(audioEngine.prepareCalled)
        XCTAssertTrue(audioEngine.startCalled)
    }

    @MainActor
    func testStartListeningInstallsTap() {
        engine.startListening()
        XCTAssertTrue(audioEngine.tapInstalled)
    }

    @MainActor
    func testStartListeningSetsIsListeningTrue() {
        engine.startListening()
        XCTAssertTrue(engine.isListening)
    }

    @MainActor
    func testStartListeningCreatesRecognitionTask() {
        engine.startListening()
        XCTAssertNotNil(speechRecognizer.lastRequest)
    }

    // MARK: - Partial Results

    @MainActor
    func testPartialResultUpdatesCurrentTranscript() async {
        engine.startListening()
        await simulateResultAndWait("Hello", isFinal: false)
        XCTAssertEqual(engine.currentTranscript, "Hello")
    }

    @MainActor
    func testPartialResultResetsSilenceTimer() async {
        engine.startListening()
        await simulateResultAndWait("Hello", isFinal: false)
        XCTAssertNotNil(timerFactory.lastFireHandler)
        XCTAssertEqual(timerFactory.lastInterval, 1.5)
    }

    // MARK: - Utterance Complete (Silence Detection)

    @MainActor
    func testSilenceTimerFiringEmitsUtterance() async {
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("What's the weather?", isFinal: false)

        timerFactory.lastFireHandler?()
        // Timer handler also uses Task { @MainActor }
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscript, "What's the weather?")
    }

    @MainActor
    func testSilenceTimerDoesNotEmitShortTranscripts() async {
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("Hi", isFinal: false)

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(emittedTranscript)
    }

    @MainActor
    func testSilenceTimerTracksEmittedOffset() async {
        var emitted: String?
        engine.onUtteranceComplete = { emitted = $0 }

        engine.startListening()
        await simulateResultAndWait("Hello world there", isFinal: false)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emitted, "Hello world there")
    }

    // MARK: - Final Results

    @MainActor
    func testFinalResultEmitsUtterance() async {
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: true)

        XCTAssertEqual(emittedTranscript, "Hello world test")
    }

    // MARK: - Stop Listening

    @MainActor
    func testStopListeningStopsAudioEngine() {
        engine.startListening()
        engine.stopListening()
        XCTAssertTrue(audioEngine.stopCalled)
    }

    @MainActor
    func testStopListeningRemovesTap() {
        engine.startListening()
        engine.stopListening()
        XCTAssertTrue(audioEngine.tapRemoved)
    }

    @MainActor
    func testStopListeningCancelsRecognitionTask() {
        engine.startListening()
        engine.stopListening()
        XCTAssertTrue(mockTask.cancelCalled)
    }

    @MainActor
    func testStopListeningSetsIsListeningFalse() {
        engine.startListening()
        engine.stopListening()
        XCTAssertFalse(engine.isListening)
    }

    @MainActor
    func testStopListeningInvalidatesSilenceTimer() async {
        engine.startListening()
        await simulateResultAndWait("Hello", isFinal: false)
        engine.stopListening()
        XCTAssertTrue(timerFactory.invalidateCalled)
    }

    // MARK: - Recognition Errors

    @MainActor
    func testRecognitionErrorReportsViaCallback() async {
        var reportedError: VoiceEngineError?
        engine.onError = { reportedError = $0 }

        engine.startListening()
        let err = NSError(domain: "SFSpeech", code: 1, userInfo: nil)
        await simulateErrorAndWait(err)

        XCTAssertEqual(reportedError, .recognitionFailed(err.localizedDescription))
    }

    // MARK: - Audio Session Errors

    @MainActor
    func testAudioSessionConfigFailureReportsError() {
        audioSession.shouldThrowOnConfigure = true
        var reportedError: VoiceEngineError?
        engine.onError = { reportedError = $0 }

        engine.startListening()

        if case .audioSessionFailed = reportedError {
            // pass
        } else {
            XCTFail("Expected audioSessionFailed, got \(String(describing: reportedError))")
        }
        XCTAssertFalse(engine.isListening)
    }

    // MARK: - Interruptions

    @MainActor
    func testAudioInterruptionBeginsStopsListening() async {
        engine.startListening()
        XCTAssertTrue(engine.isListening)

        audioSession.interruptionHandler?(true)
        // The interruption handler uses Task { @MainActor }
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertFalse(engine.isListening)
    }

    @MainActor
    func testAudioInterruptionEndsDoesNotAutoRestart() async {
        engine.startListening()
        audioSession.interruptionHandler?(true)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        audioSession.interruptionHandler?(false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertFalse(engine.isListening)
    }

    // MARK: - Double Start Prevention

    @MainActor
    func testStartListeningWhileAlreadyListeningIsNoOp() {
        engine.startListening()
        let firstRequest = speechRecognizer.lastRequest

        engine.startListening()

        XCTAssertTrue(speechRecognizer.lastRequest === firstRequest)
    }

    // MARK: - Minimum Transcript Length

    @MainActor
    func testMinimumTranscriptLengthDefaultsTo3() {
        XCTAssertEqual(engine.minimumTranscriptLength, 3)
    }

    // MARK: - Recognition Restart After Utterance

    @MainActor
    func testEmittingUtteranceCancelsCurrentRecognitionTask() async {
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("What is the weather?", isFinal: false)

        XCTAssertFalse(mockTask.cancelCalled, "Task should not be cancelled before emission")

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertTrue(mockTask.cancelCalled, "Old recognition task should be cancelled after emitting utterance")
    }

    @MainActor
    func testEmittingUtteranceStartsNewRecognitionTask() async {
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        XCTAssertEqual(speechRecognizer.taskCreationCount, 1)

        await simulateResultAndWait("What is the weather?", isFinal: false)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(speechRecognizer.taskCreationCount, 2, "A new recognition task should be created after emitting utterance")
    }

    @MainActor
    func testNewRecognitionTaskReceivesFreshTranscript() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("First utterance test", isFinal: false)

        // Emit first utterance via silence timer
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["First utterance test"])

        // The new task should have its own resultHandler via allCreatedTasks
        guard speechRecognizer.allCreatedTasks.count >= 2 else {
            XCTFail("Expected a second recognition task to be created")
            return
        }
        let newTask = speechRecognizer.allCreatedTasks[1]

        // Simulate result on the NEW task — should only contain new text
        newTask.simulateResult("Second thing", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(engine.currentTranscript, "Second thing", "New task should start with fresh transcript")
    }

    // MARK: - Transcript Accumulation Fix (Utterance Offset)

    @MainActor
    func testStopListeningClearsCurrentTranscript() async {
        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)
        XCTAssertEqual(engine.currentTranscript, "Hello world test")

        engine.stopListening()
        XCTAssertEqual(engine.currentTranscript, "", "stopListening should clear currentTranscript")
    }

    @MainActor
    func testSecondUtteranceEmitsFullTextFromNewTask() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("First utterance", isFinal: false)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["First utterance"])

        // After emit+restart, new task starts fresh. Simulate new speech.
        let latestTask = speechRecognizer.allCreatedTasks.last!
        latestTask.simulateResult("Second thing entirely", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["First utterance", "Second thing entirely"],
                       "New task starts fresh so full transcript should be emitted")
    }

    @MainActor
    func testStartListeningResetsEmittedOffset() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        engine.stopListening()

        let newTask = MockRecognitionTask()
        speechRecognizer.recognitionTaskToReturn = newTask
        engine.startListening()
        newTask.simulateResult("New session text", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["Hello world test", "New session text"])
    }

    @MainActor
    func testRestartTimerDoesNotEmitWithoutNewPartials() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("Complete sentence here", isFinal: false)

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["Complete sentence here"])

        // The restart silence timer fires without any new speech from the new task.
        // currentTranscript was set to "" by restartRecognition resetting state,
        // so there's nothing to emit.
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["Complete sentence here"],
                       "Restart timer firing with no new partials should not emit anything")
    }

    @MainActor
    func testEngineRemainsListeningAfterUtteranceEmission() async {
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertTrue(engine.isListening, "Engine should remain listening after emitting utterance")
    }

    // MARK: - Silence Timer Cleanup on Short Utterance

    @MainActor
    func testSilenceTimerInvalidatedWhenShortUtteranceRejected() async throws {
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("Hi", isFinal: false)

        // Grab the token created by resetSilenceTimer during partial result
        let timerToken = timerFactory.allTokens.last!
        XCTAssertEqual(timerToken.invalidateCount, 0)

        // Fire the timer — utterance is too short (2 chars < 3), should be rejected
        timerFactory.lastFireHandler?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(emittedTranscript, "Short utterance should not be emitted")
        XCTAssertGreaterThan(timerToken.invalidateCount, 0,
                             "Silence timer should be invalidated even when utterance is too short to emit")
    }

    // MARK: - Bug Fix: Silence timer must run after utterance restart

    @MainActor
    func testSilenceTimerRunsAfterUtteranceEmitAndRestart() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)

        // Emit via silence timer
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["Hello world test"])

        // After restart, a new silence timer should be scheduled immediately
        // (to catch the case where no new partials arrive — the user already stopped talking)
        let timerCountAfterRestart = timerFactory.allTokens.count
        XCTAssertGreaterThan(timerCountAfterRestart, 1,
                             "A silence timer should be scheduled after recognition restart so continued silence triggers a cut")
    }

    // MARK: - Bug Fix: lastEmittedLength reset after restart

    @MainActor
    func testRestartRecognitionResetsEmittedOffset() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("Have you ever told you about my Nazi knock knock joke", isFinal: false)

        // Emit first utterance via silence timer
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts.count, 1)

        // New task created by restartRecognition — simulate a completely new transcript
        let newTask = speechRecognizer.allCreatedTasks.last!
        newTask.simulateResult("Knock knock who's there", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Emit second utterance — should be the FULL new transcript, not truncated
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, [
            "Have you ever told you about my Nazi knock knock joke",
            "Knock knock who's there"
        ], "After restart, emit should use full new transcript, not drop characters from old offset")
    }

    @MainActor
    func testSilenceTimerAfterRestartFiresWithoutNewPartials() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("First sentence here", isFinal: false)

        // Emit first utterance
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["First sentence here"])

        // The restart timer fires without any new partials arriving —
        // this simulates the case where user stopped talking entirely.
        // Since there's no new text (or text is too short), it should NOT crash
        // and should NOT emit garbage.
        let restartTimerHandler = timerFactory.lastFireHandler
        XCTAssertNotNil(restartTimerHandler, "A timer handler should exist after restart")

        restartTimerHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Should still only have the first emission — no new text arrived
        XCTAssertEqual(emittedTranscripts, ["First sentence here"],
                       "Firing silence timer after restart with no new partials should not emit anything")
    }

    // MARK: - Logging

    @MainActor
    func testStartListeningLogs() {
        var logMessages: [String] = []
        engine.logHandler = { logMessages.append($0) }

        engine.startListening()

        let hasStartLog = logMessages.contains { $0.contains("startListening") }
        XCTAssertTrue(hasStartLog, "startListening should log. Got: \(logMessages)")
    }

    @MainActor
    func testStopListeningLogs() {
        var logMessages: [String] = []
        engine.logHandler = { logMessages.append($0) }

        engine.startListening()
        logMessages.removeAll()
        engine.stopListening()

        let hasStopLog = logMessages.contains { $0.contains("stopListening") }
        XCTAssertTrue(hasStopLog, "stopListening should log. Got: \(logMessages)")
    }

    @MainActor
    func testUtteranceEmissionLogs() async {
        var logMessages: [String] = []
        engine.logHandler = { logMessages.append($0) }
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)

        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        let hasEmitLog = logMessages.contains { $0.contains("utterance") }
        XCTAssertTrue(hasEmitLog, "Utterance emission should log. Got: \(logMessages)")
    }

    @MainActor
    func testAuthErrorLogs() {
        var logMessages: [String] = []
        engine.logHandler = { logMessages.append($0) }
        speechRecognizer.authorizationStatus = .denied

        engine.startListening()

        let hasErrorLog = logMessages.contains { $0.contains("notAuthorized") }
        XCTAssertTrue(hasErrorLog, "Auth error should log. Got: \(logMessages)")
    }

    @MainActor
    func testDefaultLogHandlerUsesAppLog() {
        // The default logHandler should be set (not nil)
        // We just verify the property exists and is callable
        engine.logHandler("test message")
        // No crash = success; actual AppLog integration tested elsewhere
    }
}
