import Foundation
import AVFoundation

// MARK: - Protocols for Dependency Injection

enum SpeechAuthorizationStatus {
    case authorized
    case denied
    case restricted
    case notDetermined
}

protocol SpeechRecognitionResultProtocol {
    var bestTranscriptionString: String { get }
    var isFinal: Bool { get }
}

protocol SpeechRecognitionTaskProtocol: AnyObject {
    func cancel()
    func finish()
}

protocol SpeechRecognitionRequesting: AnyObject {}

protocol SpeechRecognizing {
    var isAvailable: Bool { get }
    var authorizationStatus: SpeechAuthorizationStatus { get }
    func prepareRecognizer()
    func recognitionTask(with request: any SpeechRecognitionRequesting,
                         resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void) -> SpeechRecognitionTaskProtocol
}

protocol AudioEngineProviding {
    associatedtype Format
    associatedtype Buffer

    var isRunning: Bool { get }
    func prepare()
    func start() throws
    func stop()
    func installTap(onBus bus: Int, bufferSize: UInt32, format: Format?,
                     block: @escaping (Buffer) -> Void)
    func removeTap(onBus bus: Int)
    func inputFormat(forBus bus: Int) -> Format
}

protocol AudioSessionConfiguring {
    func configureForVoice() throws
    func setActive(_ active: Bool) throws
    func registerInterruptionHandler(_ handler: @escaping (Bool) -> Void)
}

protocol TimerToken: AnyObject {
    func invalidate()
}

protocol TimerScheduling {
    func scheduleTimer(interval: TimeInterval, handler: @escaping () -> Void) -> TimerToken
}

// MARK: - Errors

enum VoiceEngineError: Equatable {
    case notAuthorized
    case recognizerUnavailable
    case recognitionFailed(String)
    case audioSessionFailed(String)
}

// MARK: - VoiceEngine

@MainActor
final class VoiceEngine<AudioEngine: AudioEngineProviding> {
    // Published state
    var isListening = false
    var currentTranscript = ""

    // Configuration
    let silenceThreshold: TimeInterval
    let watchdogInterval: TimeInterval
    let coldStartWatchdogInterval: TimeInterval?
    let finalDebounceInterval: TimeInterval
    let minimumTranscriptLength = 3

    // Callbacks
    var onUtteranceComplete: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onError: ((VoiceEngineError) -> Void)?
    var logHandler: (String) -> Void = { AppLog.shared.log($0) }

    // Dependencies
    private let speechRecognizer: any SpeechRecognizing
    private let audioEngine: AudioEngine
    private let audioSession: any AudioSessionConfiguring
    private let timerFactory: any TimerScheduling

    // Internal state
    private var recognitionTask: SpeechRecognitionTaskProtocol?
    private var recognitionRequest: (any SpeechRecognitionRequesting)?
    private var silenceTimer: TimerToken?
    private var watchdogTimer: TimerToken?
    private var finalDebounceTimer: TimerToken?
    private var hasReceivedPartial = false
    private var lastEmittedLength = 0
    private var pendingTranscript = ""
    private var coldStartWatchdogMissCount = 0
    private var coldStartHardRestartCount = 0
    private let maxColdStartHardRestarts = 3
    private var isPerformingInternalRecoveryRestart = false
    private var hasSeenPartialInCurrentListen = false
    private var useFastColdStartWatchdog = true

    init(speechRecognizer: any SpeechRecognizing,
         audioEngine: AudioEngine,
         audioSession: any AudioSessionConfiguring,
         timerFactory: any TimerScheduling,
         silenceThreshold: TimeInterval = 1.5,
         watchdogInterval: TimeInterval = 3.0,
         coldStartWatchdogInterval: TimeInterval? = nil,
         finalDebounceInterval: TimeInterval = 3.0) {
        self.speechRecognizer = speechRecognizer
        self.audioEngine = audioEngine
        self.audioSession = audioSession
        self.timerFactory = timerFactory
        self.silenceThreshold = silenceThreshold
        self.watchdogInterval = watchdogInterval
        self.coldStartWatchdogInterval = coldStartWatchdogInterval
        self.finalDebounceInterval = finalDebounceInterval

        speechRecognizer.prepareRecognizer()

        audioSession.registerInterruptionHandler { [weak self] began in
            Task { @MainActor in
                if began {
                    self?.stopListening()
                }
            }
        }
    }

    func startListening() {
        guard !isListening else {
            logHandler("🎙️ [STT] startListening: already listening, skipping")
            return
        }

        logHandler("🎙️ [STT] startListening: beginning setup")
        lastEmittedLength = 0
        currentTranscript = ""
        if !isPerformingInternalRecoveryRestart {
            coldStartWatchdogMissCount = 0
            coldStartHardRestartCount = 0
            hasSeenPartialInCurrentListen = false
            useFastColdStartWatchdog = true
        }

        guard speechRecognizer.authorizationStatus == .authorized else {
            logHandler("🎙️ [STT] startListening: notAuthorized (status=\(speechRecognizer.authorizationStatus))")
            onError?(.notAuthorized)
            return
        }

        guard speechRecognizer.isAvailable else {
            logHandler("🎙️ [STT] startListening: recognizer unavailable")
            onError?(.recognizerUnavailable)
            return
        }

        do {
            try audioSession.configureForVoice()
            logHandler("🎙️ [STT] startListening: audio session configured")
        } catch {
            logHandler("🎙️ [STT] startListening: audio session failed: \(error.localizedDescription)")
            onError?(.audioSessionFailed(error.localizedDescription))
            return
        }

        let request = RealSpeechRecognitionRequest()
        recognitionRequest = request

        let format = audioEngine.inputFormat(forBus: 0)
        audioEngine.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer in
            // Feed audio to the real speech recognition request
            if let pcmBuffer = buffer as Any as? AVAudioPCMBuffer {
                request?.append(pcmBuffer)
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.handleRecognitionError(error)
                    return
                }
                guard let result = result else { return }

                self.currentTranscript = result.bestTranscriptionString
                if !self.hasReceivedPartial {
                    self.hasReceivedPartial = true
                    self.watchdogTimer?.invalidate()
                    self.watchdogTimer = nil
                    self.coldStartWatchdogMissCount = 0
                    self.coldStartHardRestartCount = 0
                    self.hasSeenPartialInCurrentListen = true
                    self.useFastColdStartWatchdog = true
                }
                self.onPartialTranscript?(self.currentTranscript)
                self.resetSilenceTimer()

                if result.isFinal {
                    self.logHandler("🎙️ [STT] final result: \"\(result.bestTranscriptionString.prefix(80))\"")
                    self.handleIsFinal()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            logHandler("🎙️ [STT] startListening: engine start failed: \(error.localizedDescription)")
            onError?(.audioSessionFailed(error.localizedDescription))
            return
        }

        isListening = true
        hasReceivedPartial = false
        startWatchdog()
        logHandler("🎙️ [STT] startListening: now listening")
    }

    func stopListening() {
        logHandler("🎙️ [STT] stopListening")
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        finalDebounceTimer?.invalidate()
        finalDebounceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.removeTap(onBus: 0)
        audioEngine.stop()
        isListening = false
        currentTranscript = ""
        lastEmittedLength = 0
        pendingTranscript = ""
        if !isPerformingInternalRecoveryRestart {
            hasSeenPartialInCurrentListen = false
            useFastColdStartWatchdog = true
        }
    }

    // MARK: - Private

    /// Handle a recognition error from any recognition task callback.
    /// Centralizes error handling: suppresses cold-start errors, finalizes
    /// transcript on mid-speech errors, and restarts recognition to recover.
    private func handleRecognitionError(_ error: Error) {
        guard isListening, !isCancellationError(error) else { return }
        // During cold-start grace period (before any partial result arrives),
        // suppress recognition errors — the watchdog will restart recognition.
        guard hasReceivedPartial else {
            logHandler("🎙️ [STT] suppressing cold-start recognition error: \(error.localizedDescription)")
            return
        }
        logHandler("🎙️ [STT] recognition error: \(error.localizedDescription)")
        // Finalize any pending transcript so user speech is never lost (zaap-p6h).
        // Without this, the engine hangs with a dead task and unsent transcript.
        finalizeTranscriptOnError()
        onError?(.recognitionFailed(error.localizedDescription))
    }

    /// Returns true if this error should be silently ignored (e.g. cancellation errors).
    private func isCancellationError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        let nsErr = error as NSError
        return desc.contains("cancel") || nsErr.code == 301 || nsErr.code == 216
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = timerFactory.scheduleTimer(interval: silenceThreshold) { [weak self] in
            Task { @MainActor in
                self?.emitUtteranceIfValid()
            }
        }
    }

    /// Start a watchdog timer that restarts recognition if no partial results arrive.
    /// On first app launch, SFSpeechRecognizer's on-device model may not be loaded yet,
    /// causing the first recognition task to produce zero results. The watchdog detects
    /// this and creates a fresh task.
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let interval: TimeInterval
        if !hasSeenPartialInCurrentListen, useFastColdStartWatchdog {
            interval = coldStartWatchdogInterval ?? watchdogInterval
        } else {
            interval = watchdogInterval
        }
        watchdogTimer = timerFactory.scheduleTimer(interval: interval) { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isListening, !self.hasReceivedPartial else { return }
                self.coldStartWatchdogMissCount += 1
                self.logHandler("🎙️ [STT] watchdog: no partials after \(interval)s (miss \(self.coldStartWatchdogMissCount)), restarting recognition")
                // If repeated watchdog misses occur with zero partials, perform a full
                // stop/start cycle (same recovery as manual mic toggle on device).
                if self.coldStartWatchdogMissCount >= 2, self.coldStartHardRestartCount < self.maxColdStartHardRestarts {
                    self.coldStartHardRestartCount += 1
                    // After one hard restart, back off to normal watchdog pacing
                    // to avoid rapid restart thrash while user is speaking.
                    self.useFastColdStartWatchdog = false
                    self.logHandler("🎙️ [STT] watchdog: repeated cold-start misses, performing hard restart (\(self.coldStartHardRestartCount)/\(self.maxColdStartHardRestarts))")
                    self.hardRestartListening()
                    return
                }
                self.restartRecognition()
                // Re-arm watchdog in case the model still isn't ready
                self.startWatchdog()
            }
        }
    }

    /// Fully tear down and restart listening, matching manual mic toggle behavior.
    /// Used when repeated watchdog misses indicate the recognizer/audio pipeline
    /// is wedged in a cold-start state on real devices.
    private func hardRestartListening() {
        guard isListening else { return }
        isPerformingInternalRecoveryRestart = true
        defer { isPerformingInternalRecoveryRestart = false }
        coldStartWatchdogMissCount = 0
        stopListening()
        startListening()
    }

    /// Handle Apple's isFinal by debouncing: save the transcript, restart recognition,
    /// and start a short timer. If new speech arrives quickly, it cancels the debounce
    /// and carries the old transcript forward. If not, the debounce timer emits.
    private func handleIsFinal() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.count >= minimumTranscriptLength else {
            logHandler("🎙️ [STT] isFinal transcript too short, ignoring: \"\(transcript)\"")
            restartRecognition()
            return
        }

        // Save the transcript so it can be carried forward if new speech arrives
        pendingTranscript = transcript
        logHandler("🎙️ [STT] isFinal debounce: holding \"\(transcript.prefix(80))\" pending new speech")

        restartRecognition()

        // Start a debounce timer — if no new speech arrives, emit.
        // Uses finalDebounceInterval (longer than silenceThreshold) to tolerate
        // natural pauses mid-sentence that Apple's recognizer interprets as isFinal.
        finalDebounceTimer?.invalidate()
        finalDebounceTimer = timerFactory.scheduleTimer(interval: finalDebounceInterval) { [weak self] in
            Task { @MainActor in
                self?.emitPendingTranscript()
            }
        }
    }

    /// Emit whatever is in pendingTranscript + currentTranscript (if the debounce timer fires
    /// without new speech cancelling it).
    /// Finalize any pending transcript when a recognition error occurs.
    /// Prevents the "mic cuts off mid-sentence and hangs" bug where the
    /// recognition task dies but the partial transcript is never sent.
    private func finalizeTranscriptOnError() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        finalDebounceTimer?.invalidate()
        finalDebounceTimer = nil

        let combined = buildFullTranscript()
        if combined.count >= minimumTranscriptLength {
            logHandler("🎙️ [STT] finalizing transcript on recognition error: \"\(combined.prefix(80))\"")
            onUtteranceComplete?(combined)
        }
        pendingTranscript = ""
        lastEmittedLength = 0

        // Restart recognition to recover from the dead task
        if isListening {
            restartRecognition()
        }
    }

    private func emitPendingTranscript() {
        finalDebounceTimer?.invalidate()
        finalDebounceTimer = nil

        let combined = buildFullTranscript()
        guard combined.count >= minimumTranscriptLength else {
            logHandler("🎙️ [STT] debounce expired but combined transcript too short (\(combined.count) chars)")
            pendingTranscript = ""
            return
        }

        logHandler("🎙️ [STT] debounce expired, emitting: \"\(combined.prefix(80))\"")
        onUtteranceComplete?(combined)
        pendingTranscript = ""
        lastEmittedLength = 0
        currentTranscript = ""
        restartRecognition()
    }

    /// Combine pendingTranscript and currentTranscript into a single string.
    private func buildFullTranscript() -> String {
        let pending = pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if pending.isEmpty { return current }
        if current.isEmpty { return pending }
        return pending + " " + current
    }

    private func emitUtteranceIfValid() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        let combined = buildFullTranscript()
        guard combined.count >= minimumTranscriptLength else {
            logHandler("🎙️ [STT] utterance too short (\(combined.count) chars): \"\(combined)\"")
            resetSilenceTimer()
            return
        }
        logHandler("🎙️ [STT] emitting utterance: \"\(combined.prefix(80))\"")
        onUtteranceComplete?(combined)
        pendingTranscript = ""
        lastEmittedLength = 0
        restartRecognition()
    }

    private func restartRecognition() {
        logHandler("🎙️ [STT] restartRecognition: creating new recognition task")
        // Reset transcript state — new task starts fresh.
        currentTranscript = ""
        // Reset cold-start grace period so the new task's errors are suppressed
        // until it produces its first partial result. Re-arm watchdog for recovery.
        hasReceivedPartial = false
        startWatchdog()

        // Tear down the current recognition task so the next callback does not
        // restore the old accumulated transcript into currentTranscript.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Remove the existing audio tap (it weakly held the old request).
        audioEngine.removeTap(onBus: 0)

        // Create a fresh request + tap so audio keeps flowing uninterrupted.
        let request = RealSpeechRecognitionRequest()
        recognitionRequest = request

        let format = audioEngine.inputFormat(forBus: 0)
        audioEngine.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer in
            if let pcmBuffer = buffer as Any as? AVAudioPCMBuffer {
                request?.append(pcmBuffer)
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.handleRecognitionError(error)
                    return
                }
                guard let result = result else { return }

                // Mark that this restarted task has received results,
                // ending the cold-start grace period (zaap-p6h).
                if !self.hasReceivedPartial {
                    self.hasReceivedPartial = true
                    self.watchdogTimer?.invalidate()
                    self.watchdogTimer = nil
                    self.coldStartWatchdogMissCount = 0
                    self.coldStartHardRestartCount = 0
                    self.hasSeenPartialInCurrentListen = true
                }

                // New speech arrived — if we were debouncing after isFinal,
                // cancel the debounce and let the pending transcript carry forward.
                if self.finalDebounceTimer != nil {
                    self.finalDebounceTimer?.invalidate()
                    self.finalDebounceTimer = nil
                    self.logHandler("🎙️ [STT] new speech after isFinal, carrying forward pending transcript")
                }

                // If carrying forward a pending transcript from a debounced isFinal,
                // merge it into currentTranscript and clear the pending state.
                if !self.pendingTranscript.isEmpty {
                    self.currentTranscript = self.pendingTranscript + " " + result.bestTranscriptionString
                    self.pendingTranscript = ""
                } else {
                    self.currentTranscript = result.bestTranscriptionString
                }
                self.onPartialTranscript?(self.currentTranscript)
                self.resetSilenceTimer()

                if result.isFinal {
                    self.handleIsFinal()
                }
            }
        }

        // Schedule a silence timer so that if no new partials arrive
        // (user already stopped talking), the silence cut still fires.
        resetSilenceTimer()
    }
}

// MARK: - VoiceEngineProtocol conformance

extension VoiceEngine: VoiceEngineProtocol {}

// MARK: - Concrete Request (used internally, mockable via protocol)

final class MockSpeechRecognitionRequest: SpeechRecognitionRequesting {}

// MARK: - Real Timer Factory

final class RealTimerFactory: TimerScheduling {
    func scheduleTimer(interval: TimeInterval, handler: @escaping () -> Void) -> TimerToken {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            handler()
        }
        return RealTimerToken(timer: timer)
    }
}

final class RealTimerToken: TimerToken {
    private let timer: Timer
    init(timer: Timer) { self.timer = timer }
    func invalidate() { timer.invalidate() }
}
