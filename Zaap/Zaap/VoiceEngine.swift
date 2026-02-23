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
    let minimumTranscriptLength = 3

    // Callbacks
    var onUtteranceComplete: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onError: ((VoiceEngineError) -> Void)?

    // Dependencies
    private let speechRecognizer: any SpeechRecognizing
    private let audioEngine: AudioEngine
    private let audioSession: any AudioSessionConfiguring
    private let timerFactory: any TimerScheduling

    // Internal state
    private var recognitionTask: SpeechRecognitionTaskProtocol?
    private var recognitionRequest: (any SpeechRecognitionRequesting)?
    private var silenceTimer: TimerToken?

    init(speechRecognizer: any SpeechRecognizing,
         audioEngine: AudioEngine,
         audioSession: any AudioSessionConfiguring,
         timerFactory: any TimerScheduling,
         silenceThreshold: TimeInterval = 1.5) {
        self.speechRecognizer = speechRecognizer
        self.audioEngine = audioEngine
        self.audioSession = audioSession
        self.timerFactory = timerFactory
        self.silenceThreshold = silenceThreshold

        audioSession.registerInterruptionHandler { [weak self] began in
            Task { @MainActor in
                if began {
                    self?.stopListening()
                }
            }
        }
    }

    func startListening() {
        guard !isListening else { return }

        guard speechRecognizer.authorizationStatus == .authorized else {
            onError?(.notAuthorized)
            return
        }

        guard speechRecognizer.isAvailable else {
            onError?(.recognizerUnavailable)
            return
        }

        do {
            try audioSession.configureForVoice()
        } catch {
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
                    // Ignore errors that fire after we intentionally stopped listening
                    // (e.g. kAFAssistantErrorDomain 216 from cancelling the recognition task)
                    guard self.isListening else { return }
                    self.onError?(.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let result = result else { return }

                self.currentTranscript = result.bestTranscriptionString
                self.onPartialTranscript?(self.currentTranscript)
                self.resetSilenceTimer()

                if result.isFinal {
                    self.emitUtteranceIfValid()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?(.audioSessionFailed(error.localizedDescription))
            return
        }

        isListening = true
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.removeTap(onBus: 0)
        audioEngine.stop()
        isListening = false
    }

    // MARK: - Private

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = timerFactory.scheduleTimer(interval: silenceThreshold) { [weak self] in
            Task { @MainActor in
                self?.emitUtteranceIfValid()
            }
        }
    }

    private func emitUtteranceIfValid() {
        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.count >= minimumTranscriptLength else { return }
        onUtteranceComplete?(transcript)
        currentTranscript = ""
        silenceTimer?.invalidate()
        silenceTimer = nil
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
