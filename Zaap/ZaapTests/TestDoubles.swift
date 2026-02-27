import Foundation
import CoreLocation
import Combine
import AVFoundation
@testable import Zaap

// MARK: - Mock Webhook Client

final class MockWebhookClient: WebhookPosting, @unchecked Sendable {
    var postCallCount = 0
    var lastPath: String?
    var lastPayloadData: Data?
    var shouldThrow: Error?

    func post<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        postCallCount += 1
        lastPath = path
        lastPayloadData = try JSONEncoder().encode(payload)
        if let error = shouldThrow {
            throw error
        }
    }

    func postForeground<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        try await post(payload, to: path)
    }
}

// MARK: - Mock Location Publisher

@MainActor
final class MockLocationPublishing: LocationPublishing {
    let locationPublisher = PassthroughSubject<CLLocation, Never>()
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var isMonitoring = false
    var currentLocation: CLLocation?
    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0

    func startMonitoring() {
        startMonitoringCallCount += 1
        isMonitoring = true
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        isMonitoring = false
    }
}

// MARK: - Mock Sleep Reader

final class MockSleepReader: SleepReading {
    var authorizationRequested = false
    var summaryToReturn: SleepDataReader.SleepSummary?
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchLastNightSummary() async throws -> SleepDataReader.SleepSummary {
        if let error = shouldThrow {
            throw error
        }
        guard let summary = summaryToReturn else {
            throw SleepDataReader.SleepError.noData
        }
        return summary
    }
}

// MARK: - Mock Heart Rate Reader

final class MockHeartRateReader: HeartRateReading {
    var authorizationRequested = false
    var summaryToReturn: HeartRateReader.DailyHeartRateSummary?
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchDailySummary(for date: Date) async throws -> HeartRateReader.DailyHeartRateSummary {
        if let error = shouldThrow {
            throw error
        }
        guard let summary = summaryToReturn else {
            throw HeartRateReader.HeartRateError.noData
        }
        return summary
    }
}

// MARK: - Mock Activity Reader

final class MockActivityReader: ActivityReading {
    var authorizationRequested = false
    var summaryToReturn: ActivityReader.ActivitySummary?
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchTodaySummary() async throws -> ActivityReader.ActivitySummary {
        if let error = shouldThrow {
            throw error
        }
        guard let summary = summaryToReturn else {
            throw ActivityReader.ActivityError.noData
        }
        return summary
    }
}

// MARK: - Mock Delivery Log

final class MockDeliveryLogService: DeliveryLogging {
    var records: [(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String?)] = []

    func record(dataType: DeliveryDataType, timestamp: Date, success: Bool, errorMessage: String?) {
        records.append((dataType: dataType, timestamp: timestamp, success: success, errorMessage: errorMessage))
    }
}

// MARK: - Mock Keychain Access

final class MockKeychainAccess: KeychainAccessing {
    var savedKeys: [String: Data] = [:]
    var shouldThrow: Error?

    func save(key: String, data: Data) throws {
        if let error = shouldThrow { throw error }
        savedKeys[key] = data
    }

    func load(key: String) -> Data? {
        return savedKeys[key]
    }

    func delete(key: String) {
        savedKeys.removeValue(forKey: key)
    }
}

// MARK: - Mock Workout Reader

final class MockWorkoutReader: WorkoutReading {
    var authorizationRequested = false
    var sessionsToReturn: [WorkoutReader.WorkoutSession] = []
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchRecentSessions(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutReader.WorkoutSession] {
        if let error = shouldThrow {
            throw error
        }
        return sessionsToReturn
    }
}

// MARK: - Mock Voice Engine

final class MockVoiceEngine: VoiceEngineProtocol {
    var isListening = false
    var currentTranscript = ""
    var onUtteranceComplete: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onError: ((VoiceEngineError) -> Void)?
    var startListeningCalled = false
    var stopListeningCalled = false

    func startListening() {
        startListeningCalled = true
        isListening = true
    }

    func stopListening() {
        stopListeningCalled = true
        isListening = false
    }
}

// MARK: - Mock Gateway Connecting

final class MockGatewayConnecting: GatewayConnecting {
    var state: ConnectionState = .disconnected
    weak var delegate: GatewayConnectionDelegate?
    var connectURL: URL?
    var disconnectCalled = false
    var sentTranscripts: [(text: String, sessionKey: String)] = []
    var shouldThrowOnSend: Error?

    func connect(to url: URL) {
        connectURL = url
        state = .connecting
    }

    func disconnect() {
        disconnectCalled = true
        state = .disconnected
    }

    func sendVoiceTranscript(_ text: String, sessionKey: String) async throws {
        if let error = shouldThrowOnSend { throw error }
        sentTranscripts.append((text: text, sessionKey: sessionKey))
    }

    var sessionsToReturn: [GatewaySession] = []

    func listSessions(limit: Int, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession] {
        return sessionsToReturn
    }

    func simulateConnect() {
        state = .connected
        delegate?.gatewayDidConnect()
    }

    func simulateDisconnect() {
        state = .disconnected
        delegate?.gatewayDidDisconnect()
    }

    func simulateEvent(_ event: String, payload: [String: Any]) {
        delegate?.gatewayDidReceiveEvent(event, payload: payload)
    }

    func simulateError(_ error: GatewayConnectionError) {
        delegate?.gatewayDidFailWithError(error)
    }
}

// MARK: - Mock Response Speaking

final class MockResponseSpeaking: ResponseSpeaking {
    var state: SpeakerState = .idle
    var spokenTexts: [String] = []
    var bufferedTokens: [String] = []
    var flushCalled = false
    var interruptCalled = false

    func speakImmediate(_ text: String) {
        spokenTexts.append(text)
        state = .speaking
    }

    func bufferToken(_ token: String) {
        bufferedTokens.append(token)
    }

    func flush() {
        flushCalled = true
    }

    func interrupt() {
        interruptCalled = true
        state = .idle
    }
}

// MARK: - Mock Speech Synthesizer

final class MockSpeechSynthesizer: SpeechSynthesizing {
    weak var delegate: (any AVSpeechSynthesizerDelegate)?
    var isSpeakingValue = false
    var isSpeaking: Bool { isSpeakingValue }
    var spokenTexts: [String] = []
    var spokenUtterances: [AVSpeechUtterance] = []
    var stopCalled = false

    func speak(_ utterance: AVSpeechUtterance) {
        spokenTexts.append(utterance.speechString)
        spokenUtterances.append(utterance)
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCalled = true
        return true
    }

    /// Simulate the delegate callback when an utterance finishes.
    func simulateDidFinish() {
        if let speaker = delegate as? ResponseSpeaker {
            speaker.handleDidFinish()
        }
    }
}
