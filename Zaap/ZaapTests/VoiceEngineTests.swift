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
    var prepareRecognizerCallCount = 0

    func prepareRecognizer() {
        prepareRecognizerCallCount += 1
    }

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
    var startCallCount = 0
    var stopCallCount = 0
    var tapInstalled = false
    var tapRemoved = false

    func prepare() { prepareCalled = true }

    func start() throws {
        startCalled = true
        startCallCount += 1
        isRunning = true
    }

    func stop() {
        stopCalled = true
        stopCallCount += 1
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

    // MARK: - Final Results (Debounced)

    @MainActor
    func testFinalResultDoesNotEmitImmediately() async {
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: true)

        XCTAssertNil(emittedTranscript, "isFinal should NOT emit immediately — it should debounce")
    }

    @MainActor
    func testFinalResultEmitsAfterDebounceTimer() async {
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: true)

        // Fire the debounce timer that isFinal should have started
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscript, "Hello world test")
    }

    @MainActor
    func testFinalResultCarriesForwardTranscriptWhenNewSpeechArrives() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("I was saying", isFinal: true)

        // isFinal fired, but user is still talking. A new recognition task starts.
        // Simulate new speech arriving on the new task — this should carry forward
        // the old transcript and cancel the debounce.
        let newTask = speechRecognizer.allCreatedTasks.last!
        newTask.simulateResult("something important", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Should NOT have emitted yet — the debounce was cancelled by new speech
        XCTAssertTrue(emittedTranscripts.isEmpty, "Should not emit when new speech cancels the debounce")

        // The current transcript should include both old + new text
        XCTAssertEqual(engine.currentTranscript, "I was saying something important",
                       "Transcript from before isFinal should be carried forward")
    }

    @MainActor
    func testFinalResultCarriedTranscriptEmitsAsOneSentence() async {
        var emittedTranscripts: [String] = []
        engine.onUtteranceComplete = { text in emittedTranscripts.append(text) }

        engine.startListening()
        await simulateResultAndWait("I was saying", isFinal: true)

        // New speech arrives on the new task — carries forward
        let newTask = speechRecognizer.allCreatedTasks.last!
        newTask.simulateResult("something important", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Now silence timer fires — should emit the FULL combined transcript
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscripts, ["I was saying something important"],
                       "Carried-forward transcript + new speech should emit as one complete message")
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
        // Send a partial first so cold-start grace period ends
        await simulateResultAndWait("Hello", isFinal: false)
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

    // MARK: - Cold Start Watchdog

    @MainActor
    func testWatchdogRestartsRecognitionWhenNoPartialsArrive() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        XCTAssertEqual(speechRecognizer.taskCreationCount, 1)

        // Simulate watchdog timer firing (no partials arrived)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Should have restarted recognition — new task created
        XCTAssertEqual(speechRecognizer.taskCreationCount, 2,
                       "Watchdog should restart recognition when no partials arrive")
        XCTAssertTrue(engine.isListening, "Engine should still be listening after watchdog restart")
    }

    @MainActor
    func testWatchdogCancelledWhenPartialArrives() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )

        engine.startListening()

        // Grab the watchdog timer token
        let watchdogToken = timerFactory.allTokens.first!

        // Simulate a partial result arriving — watchdog should be cancelled
        await simulateResultAndWait("Hello", isFinal: false)

        XCTAssertGreaterThan(watchdogToken.invalidateCount, 0,
                             "Watchdog timer should be cancelled when first partial arrives")
    }

    @MainActor
    func testWatchdogDoesNotFireAfterStop() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )

        engine.startListening()
        engine.stopListening()

        // Fire watchdog after stop
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Should NOT restart — only the initial task should exist
        XCTAssertEqual(speechRecognizer.taskCreationCount, 1,
                       "Watchdog should not restart recognition after stopListening")
    }

    @MainActor
    func testWatchdogDefaultsTo3Seconds() {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5
        )

        engine.startListening()

        // The first timer scheduled should be the watchdog at 3.0s
        XCTAssertEqual(timerFactory.allTokens.count, 1)
        XCTAssertEqual(timerFactory.lastInterval, 3.0,
                       "Watchdog should default to 3 seconds")
    }

    // MARK: - Cold Start Error Suppression

    @MainActor
    func testRecognitionErrorSuppressedDuringColdStartGracePeriod() async {
        var reportedError: VoiceEngineError?
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.onError = { reportedError = $0 }

        engine.startListening()

        // Simulate a recognition error before any partial result arrives
        // (this is the cold-start "No speech detected" scenario)
        let err = NSError(domain: "kAFAssistantErrorDomain", code: 1110,
                          userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        mockTask.simulateError(err)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(reportedError,
                     "Recognition errors should be suppressed during cold-start grace period (before any partial arrives)")
        XCTAssertTrue(engine.isListening,
                      "Engine should remain listening after suppressed cold-start error")
    }

    @MainActor
    func testRecognitionErrorForwardedAfterFirstPartialArrives() async {
        var reportedError: VoiceEngineError?
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.onError = { reportedError = $0 }

        engine.startListening()

        // First, a partial result arrives (grace period ends)
        await simulateResultAndWait("Hello", isFinal: false)

        // Now simulate a recognition error — should be forwarded normally
        let err = NSError(domain: "SFSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Recognition failed"])
        mockTask.simulateError(err)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(reportedError, .recognitionFailed("Recognition failed"),
                       "Recognition errors should be forwarded after grace period ends (partial received)")
    }

    @MainActor
    func testColdStartErrorSuppressionLogs() async {
        var logMessages: [String] = []
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.logHandler = { logMessages.append($0) }

        engine.startListening()

        let err = NSError(domain: "kAFAssistantErrorDomain", code: 1110,
                          userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        mockTask.simulateError(err)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        let hasSuppressLog = logMessages.contains { $0.contains("cold-start") || $0.contains("suppressing") }
        XCTAssertTrue(hasSuppressLog,
                      "Suppressed cold-start errors should be logged. Got: \(logMessages)")
    }

    @MainActor
    func testWatchdogLogsRestart() async {
        var logMessages: [String] = []
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.logHandler = { logMessages.append($0) }
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        let hasWatchdogLog = logMessages.contains { $0.contains("watchdog") }
        XCTAssertTrue(hasWatchdogLog, "Watchdog restart should log. Got: \(logMessages)")
    }

    @MainActor
    func testFastColdStartWatchdogBacksOffAfterHardRestart() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0,
            coldStartWatchdogInterval: 1.0
        )

        engine.startListening()
        XCTAssertEqual(timerFactory.lastInterval, 1.0,
                       "Initial cold-start watchdog should use fast interval")

        // miss 1 -> restartRecognition (still fast path)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // miss 2 -> hard restart, then watchdog should back off to normal interval
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(timerFactory.lastInterval, 3.0,
                       "After hard restart, watchdog should back off to normal interval")
    }

    @MainActor
    func testRepeatedColdStartWatchdogTriggersHardRestart() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )

        engine.startListening()
        XCTAssertEqual(audioEngine.startCallCount, 1)
        XCTAssertEqual(audioEngine.stopCallCount, 0)

        // First watchdog miss: normal recognition-task restart.
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Second consecutive watchdog miss with no partials: hard restart (stop/start).
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertGreaterThanOrEqual(audioEngine.stopCallCount, 1,
                                    "Engine should perform a hard stop after repeated cold-start misses")
        XCTAssertGreaterThanOrEqual(audioEngine.startCallCount, 2,
                                    "Engine should perform a fresh start after hard cold-start recovery")
        XCTAssertTrue(engine.isListening)
    }

    @MainActor
    func testColdStartWatchdogCanHardRestartMoreThanOnce() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )

        engine.startListening()

        // First hard-restart cycle (2 misses)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Second hard-restart cycle (2 more misses)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertGreaterThanOrEqual(audioEngine.stopCallCount, 2,
                                    "Engine should be able to hard-restart multiple times if cold-start persists")
        XCTAssertGreaterThanOrEqual(audioEngine.startCallCount, 3)
        XCTAssertTrue(engine.isListening)
    }

    // MARK: - Speech Recognizer Pre-warm

    @MainActor
    func testInitPrewarmsSpeechRecognizer() {
        // VoiceEngine should call prepareRecognizer() during init to pre-load
        // the on-device speech model, avoiding cold-start delays on first mic tap
        XCTAssertEqual(speechRecognizer.prepareRecognizerCallCount, 1,
                       "VoiceEngine should pre-warm speech recognizer during init")
    }

    @MainActor
    func testStartListeningDoesNotPrewarmAgain() {
        // prepareRecognizer was already called in init; startListening should not call it again
        let countBeforeStart = speechRecognizer.prepareRecognizerCallCount
        engine.startListening()
        XCTAssertEqual(speechRecognizer.prepareRecognizerCallCount, countBeforeStart,
                       "startListening should not call prepareRecognizer again — init already did it")
    }

    // MARK: - Bug Fix: Mic cuts off mid-sentence and hangs (zaap-p6h)

    @MainActor
    func testRecognitionErrorAfterPartialsFinalizesTranscript() async {
        // When recognition errors after partials were received, the partial
        // transcript must be finalized (emitted) so it's not lost.
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("What's the weather in", isFinal: false)

        // Recognition task dies with an error mid-sentence
        let err = NSError(domain: "SFSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Recognition failed"])
        await simulateErrorAndWait(err)

        XCTAssertEqual(emittedTranscript, "What's the weather in",
                       "Partial transcript must be finalized when recognition errors — never lose user speech")
    }

    @MainActor
    func testRecognitionErrorAfterPartialsRestartsRecognition() async {
        // After an error with valid partials, recognition must restart
        // so the engine doesn't hang with a dead task.
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        XCTAssertEqual(speechRecognizer.taskCreationCount, 1)

        await simulateResultAndWait("Tell me about", isFinal: false)

        let err = NSError(domain: "SFSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Recognition failed"])
        await simulateErrorAndWait(err)

        XCTAssertGreaterThan(speechRecognizer.taskCreationCount, 1,
                             "Recognition must restart after error to prevent dead-task hang")
        XCTAssertTrue(engine.isListening, "Engine must remain listening after error recovery")
    }

    @MainActor
    func testRecognitionErrorWithPendingDebounceFinalizesAll() async {
        // If isFinal set a pendingTranscript (debounce) and then the new task
        // errors before producing results, the pending transcript must be emitted.
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        // First partial, then isFinal → sets pendingTranscript
        await simulateResultAndWait("I was saying", isFinal: true)

        // Now on the restarted task — simulate an error before any partials
        // Note: hasReceivedPartial was reset by restartRecognition, but pendingTranscript is set
        let newTask = speechRecognizer.allCreatedTasks.last!

        // Send a partial first so we exit cold-start grace period
        newTask.simulateResult("something", isFinal: false)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Now error — should finalize pending + current
        let err = NSError(domain: "SFSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Recognition failed"])
        newTask.simulateError(err)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(emittedTranscript, "I was saying something",
                       "Both pending (from isFinal debounce) and current transcript must be finalized on error")
    }

    @MainActor
    func testRecognitionErrorWithShortTranscriptDoesNotEmit() async {
        // If the partial transcript is too short when error occurs, don't emit
        // but still restart recognition.
        var emittedTranscript: String?
        engine.onUtteranceComplete = { emittedTranscript = $0 }

        engine.startListening()
        await simulateResultAndWait("Hi", isFinal: false)

        let err = NSError(domain: "SFSpeech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Recognition failed"])
        await simulateErrorAndWait(err)

        XCTAssertNil(emittedTranscript,
                     "Short transcript should not be emitted even on error")
        XCTAssertGreaterThan(speechRecognizer.taskCreationCount, 1,
                             "Recognition should still restart even when transcript is too short")
    }

    // MARK: - Bug Fix: Silence timer dies after empty emission (zaap-6k2)

    @MainActor
    func testSilenceTimerRearmsAfterShortUtteranceRejection() async {
        // Reproduce: speak → emit → restart → silence timer fires on empty transcript
        // The timer should re-arm itself so the engine doesn't go dead.
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)

        // Emit first utterance via silence timer
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // restartRecognition arms a silence timer. It fires with no new speech
        // (currentTranscript is "" after restart, pendingTranscript is "").
        let timerCountBeforeSecondFire = timerFactory.allTokens.count
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // After rejecting the empty transcript, a new silence timer must be scheduled
        // so the engine doesn't go dead.
        XCTAssertGreaterThan(timerFactory.allTokens.count, timerCountBeforeSecondFire,
                             "Silence timer must re-arm after rejecting a too-short utterance, or the engine goes dead")
    }

    @MainActor
    func testWatchdogCanRearmAfterRecognitionRestart() async {
        // After first partial arrives, hasReceivedPartial = true and watchdog is cancelled.
        // After restartRecognition(), hasReceivedPartial should reset so the watchdog
        // can protect against the new recognition task producing no results.
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        XCTAssertEqual(speechRecognizer.taskCreationCount, 1)

        // First partial arrives — watchdog gets cancelled
        await simulateResultAndWait("Hello world test", isFinal: false)

        // Emit via silence timer → restartRecognition
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertEqual(speechRecognizer.taskCreationCount, 2)

        // The restart silence timer fires with empty text → rejected.
        // Now fire what should be a watchdog-style recovery:
        // simulate the silence timer firing again (no partials on new task)
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Fire again — the watchdog or silence timer should keep the engine alive.
        // The engine should NOT be in a dead state with no timers.
        let lastHandler = timerFactory.lastFireHandler
        XCTAssertNotNil(lastHandler,
                        "Engine must always have an active timer handler after recognition restart")
    }

    // MARK: - Bug Fix: 'No speech detected' after restart (zaap-w8d)

    @MainActor
    func testRecognitionErrorSuppressedAfterIsFinalRestart() async {
        // Scenario: user speaks, partials arrive (hasReceivedPartial=true),
        // isFinal fires, recognition restarts. The NEW task fires a 'No speech
        // detected' error before any partial arrives on it. This error should
        // be suppressed (it's a cold-start for the new task).
        var reportedError: VoiceEngineError?
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.onError = { reportedError = $0 }
        engine.onUtteranceComplete = { _ in }

        engine.startListening()

        // Partial arrives — grace period ends for first task
        await simulateResultAndWait("Hello world test", isFinal: false)

        // isFinal fires → handleIsFinal → restartRecognition
        await simulateResultAndWait("Hello world test", isFinal: true)

        // Now on the NEW recognition task, a 'No speech detected' error fires
        // before any partial arrives on the new task.
        let newTask = speechRecognizer.allCreatedTasks.last!
        let err = NSError(domain: "kAFAssistantErrorDomain", code: 1110,
                          userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        newTask.simulateError(err)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(reportedError,
                     "Recognition errors on a restarted task should be suppressed during its cold-start grace period")
    }

    @MainActor
    func testRecognitionErrorSuppressedAfterSilenceEmitRestart() async {
        // Same scenario but triggered by silence timer emission instead of isFinal
        var reportedError: VoiceEngineError?
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0
        )
        engine.onError = { reportedError = $0 }
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("Hello world test", isFinal: false)

        // Silence timer fires → emitUtteranceIfValid → restartRecognition
        timerFactory.lastFireHandler?()
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        // Error on the new task before any partial
        let newTask = speechRecognizer.allCreatedTasks.last!
        let err = NSError(domain: "kAFAssistantErrorDomain", code: 1110,
                          userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        newTask.simulateError(err)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(reportedError,
                     "Recognition errors after silence-timer restart should be suppressed during grace period")
    }

    // MARK: - Bug Fix: isFinal debounce uses longer interval (zaap-aql)

    @MainActor
    func testFinalDebounceIntervalDefaultsTo3Seconds() {
        XCTAssertEqual(engine.finalDebounceInterval, 3.0,
                       "isFinal debounce should default to 3.0s to tolerate natural speech pauses")
    }

    @MainActor
    func testFinalDebounceUsesLongerIntervalThanSilenceThreshold() async {
        // Create engine with explicit values to verify they're independent
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0,
            finalDebounceInterval: 4.0
        )
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("I was thinking about", isFinal: true)

        // The debounce timer after isFinal should use finalDebounceInterval (4.0s),
        // NOT silenceThreshold (1.5s)
        XCTAssertEqual(timerFactory.lastInterval, 4.0,
                       "isFinal debounce should use finalDebounceInterval, not silenceThreshold")
    }

    @MainActor
    func testNormalSilenceTimerStillUsesSilenceThreshold() async {
        engine = VoiceEngine(
            speechRecognizer: speechRecognizer,
            audioEngine: audioEngine,
            audioSession: audioSession,
            timerFactory: timerFactory,
            silenceThreshold: 1.5,
            watchdogInterval: 3.0,
            finalDebounceInterval: 4.0
        )
        engine.onUtteranceComplete = { _ in }

        engine.startListening()
        await simulateResultAndWait("Hello world", isFinal: false)

        // Normal partial results should use the standard silenceThreshold
        XCTAssertEqual(timerFactory.lastInterval, 1.5,
                       "Normal silence timer should still use silenceThreshold")
    }
}
