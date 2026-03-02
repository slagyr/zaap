import AVFoundation
import Network
import Security
import Speech

// MARK: - Real SFSpeechRecognizer Adapter

final class RealSpeechRecognizer: SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

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
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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

        guard let recognizer = recognizer else {
            resultHandler(nil, NSError(domain: "SpeechRecognition", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"]))
            return NoOpRecognitionTask()
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

final class NoOpRecognitionTask: SpeechRecognitionTaskProtocol {
    func cancel() {}
    func finish() {}
}

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
    let rawEngine = AVAudioEngine()
    private var engine: AVAudioEngine { rawEngine }

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
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
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

// MARK: - Production WebSocket Factory

final class URLSessionWebSocketFactory: WebSocketFactory {
    func createWebSocketTask(with url: URL) -> WebSocketTaskProtocol {
        URLSession.shared.webSocketTask(with: url)
    }
}

// MARK: - Production Keychain

final class RealKeychain: KeychainAccessing {
    private let service = "co.airworthy.zaap"

    func save(key: String, data: Data) throws {
        // Delete any pre-existing item (including old iCloud-synced ones) before saving
        let deleteQuery: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Save as device-local only — never sync to iCloud Keychain.
        // This ensures each physical device gets its own independent node identity.
        let addQuery: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          key,
            kSecAttrSynchronizable as String:   kCFBooleanFalse!,
            kSecValueData as String:            data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(key: String) -> Data? {
        // Only load device-local items — ignore any iCloud-synced ones from other devices
        let query: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          key,
            kSecAttrSynchronizable as String:   kCFBooleanFalse!,
            kSecReturnData as String:           true,
            kSecMatchLimit as String:           kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(key: String) {
        // Delete all matching items regardless of synchronizability
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
}

// MARK: - Production Network Monitor

final class NWNetworkMonitor: NetworkPathMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "co.airworthy.zaap.nwmonitor")
    private(set) var isConnected: Bool = true

    func start(onPathUpdate: @escaping (Bool) -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            self?.isConnected = connected
            onPathUpdate(connected)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

// MARK: - Simulator Keychain (UserDefaults-backed)

/// A KeychainAccessing implementation backed by UserDefaults.
/// Used in the iOS Simulator where the real Keychain is wiped on each reinstall,
/// causing device IDs to change. UserDefaults persists across reinstalls in the simulator.
final class SimulatorKeychain: KeychainAccessing {
    private let defaults: UserDefaults

    init(suiteName: String = "co.airworthy.zaap.simulatorkeychain") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func save(key: String, data: Data) throws {
        defaults.set(data, forKey: key)
    }

    func load(key: String) -> Data? {
        return defaults.data(forKey: key)
    }

    func delete(key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Real TTS Buffer Synthesizer

/// Wraps AVSpeechSynthesizer.write() to deliver PCM buffers and marker callbacks.
/// Converts Float16 buffers to Float32 for AVAudioPlayerNode compatibility.
final class RealTTSBufferSynthesizer: TTSBufferSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()

    func synthesize(utterance: AVSpeechUtterance,
                    bufferCallback: @escaping (AVAudioBuffer) -> Void,
                    markerCallback: @escaping (NSRange) -> Void,
                    finishCallback: @escaping () -> Void) {
        synthesizer.write(utterance) { buffer in
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

            // write() delivers empty buffer with 0 frames to signal completion
            guard pcmBuffer.frameLength > 0 else {
                finishCallback()
                return
            }

            // Convert Float16 to Float32 if needed
            if let converted = Self.convertToFloat32(pcmBuffer) {
                bufferCallback(converted)
            } else {
                bufferCallback(pcmBuffer)
            }
        }
    }

    func cancelSynthesis() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Convert a Float16 PCM buffer to Float32 for AVAudioPlayerNode.
    static func convertToFloat32(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.format.commonFormat != .pcmFormatFloat32 else { return nil }

        guard let float32Format = AVAudioFormat(
            standardFormatWithSampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount
        ) else { return nil }

        guard let converter = AVAudioConverter(from: buffer.format, to: float32Format) else { return nil }

        guard let output = AVAudioPCMBuffer(
            pcmFormat: float32Format,
            frameCapacity: buffer.frameCapacity
        ) else { return nil }

        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return nil }
        return output
    }
}

// MARK: - Real Audio Player Node

/// Wraps AVAudioPlayerNode for protocol-based injection.
final class RealAudioPlayerNode: AudioPlayerNodeProtocol {
    let node = AVAudioPlayerNode()

    func play() { node.play() }
    func pause() { node.pause() }
    func stop() { node.stop() }
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        node.scheduleBuffer(buffer)
    }
}

// MARK: - Real Playback Engine

/// Wraps AVAudioEngine for TTS output, sharing the same engine used for mic capture.
final class RealPlaybackEngine: PlaybackEngineProtocol {
    private let engine: AVAudioEngine

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    func attachPlayerNode(_ node: AudioPlayerNodeProtocol) {
        guard let realNode = node as? RealAudioPlayerNode else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        engine.attach(realNode.node)
        if wasRunning {
            try? engine.start()
        }
        print("🔊 [TTS] attachPlayerNode: wasRunning=\(wasRunning) isRunning=\(engine.isRunning)")
    }

    func connectPlayerNode(_ node: AudioPlayerNodeProtocol, format: AVAudioFormat?) {
        guard let realNode = node as? RealAudioPlayerNode else { return }
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let connectFormat: AVAudioFormat
        if let format = format {
            connectFormat = format
        } else if mixerFormat.channelCount > 0 && mixerFormat.sampleRate > 0 {
            connectFormat = mixerFormat
        } else {
            connectFormat = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        }
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        engine.connect(realNode.node, to: engine.mainMixerNode, format: connectFormat)
        if wasRunning {
            try? engine.start()
        }
        print("🔊 [TTS] connectPlayerNode: format=\(connectFormat) mixerFormat=\(mixerFormat) wasRunning=\(wasRunning) isRunning=\(engine.isRunning)")
    }

    func start() throws {
        guard !engine.isRunning else {
            print("🔊 [TTS] start: engine already running, skipping")
            return
        }
        engine.prepare()
        try engine.start()
        print("🔊 [TTS] start: engine started successfully")
    }

    func detachPlayerNode(_ node: AudioPlayerNodeProtocol) {
        guard let realNode = node as? RealAudioPlayerNode else { return }
        realNode.node.stop()
        engine.disconnectNodeOutput(realNode.node)
        engine.detach(realNode.node)
        print("🔊 [TTS] detachPlayerNode: done")
    }
}
