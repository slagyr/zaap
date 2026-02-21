import AVFoundation
import Speech

// MARK: - Real SFSpeechRecognizer Adapter

final class RealSpeechRecognizer: SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer

    var isAvailable: Bool { recognizer.isAvailable }

    var authorizationStatus: SpeechAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!
    }

    static func requestAuthorization(_ handler: @escaping (SpeechAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized: handler(.authorized)
            case .denied: handler(.denied)
            case .restricted: handler(.restricted)
            case .notDetermined: handler(.notDetermined)
            @unknown default: handler(.notDetermined)
            }
        }
    }

    func recognitionTask(with request: any SpeechRecognitionRequesting,
                         resultHandler: @escaping (SpeechRecognitionResultProtocol?, Error?) -> Void) -> SpeechRecognitionTaskProtocol {
        let sfRequest: SFSpeechRecognitionRequest
        if let realRequest = request as? RealSpeechRecognitionRequest {
            sfRequest = realRequest.request
        } else {
            sfRequest = SFSpeechAudioBufferRecognitionRequest()
        }

        let task = recognizer.recognitionTask(with: sfRequest) { result, error in
            if let result = result {
                resultHandler(RealRecognitionResult(result: result), error)
            } else {
                resultHandler(nil, error)
            }
        }
        return RealRecognitionTask(task: task)
    }
}

// MARK: - Real Recognition Task

final class RealRecognitionTask: SpeechRecognitionTaskProtocol {
    private let task: SFSpeechRecognitionTask

    init(task: SFSpeechRecognitionTask) {
        self.task = task
    }

    func cancel() { task.cancel() }
    func finish() { task.finish() }
}

// MARK: - Real Recognition Result

struct RealRecognitionResult: SpeechRecognitionResultProtocol {
    let result: SFSpeechRecognitionResult

    var bestTranscriptionString: String { result.bestTranscription.formattedString }
    var isFinal: Bool { result.isFinal }
}

// MARK: - Real Speech Recognition Request

final class RealSpeechRecognitionRequest: SpeechRecognitionRequesting {
    let request: SFSpeechAudioBufferRecognitionRequest

    init() {
        request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func endAudio() {
        request.endAudio()
    }
}

// MARK: - Real AVAudioEngine Adapter

final class RealAudioEngineProvider: AudioEngineProviding {
    private let engine = AVAudioEngine()

    var isRunning: Bool { engine.isRunning }

    func prepare() { engine.prepare() }

    func start() throws { try engine.start() }

    func stop() { engine.stop() }

    func installTap(onBus bus: Int, bufferSize: UInt32, format: AVAudioFormat?,
                     block: @escaping (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format) { buffer, _ in
            block(buffer)
        }
    }

    func removeTap(onBus bus: Int) {
        engine.inputNode.removeTap(onBus: bus)
    }

    func inputFormat(forBus bus: Int) -> AVAudioFormat {
        engine.inputNode.outputFormat(forBus: bus)
    }
}

// MARK: - Real Audio Session Configurator

final class RealAudioSessionConfigurator: AudioSessionConfiguring {
    private var interruptionObserver: NSObjectProtocol?

    func configureForVoice() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }

    func setActive(_ active: Bool) throws {
        try AVAudioSession.sharedInstance().setActive(active)
    }

    func registerInterruptionHandler(_ handler: @escaping (Bool) -> Void) {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            handler(type == .began)
        }
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
