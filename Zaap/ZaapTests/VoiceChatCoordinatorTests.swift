import XCTest
@testable import Zaap

// MARK: - Tests

@MainActor
final class VoiceChatCoordinatorTests: XCTestCase {

    var voiceEngine: MockVoiceEngine!
    var gateway: MockGatewayConnecting!
    var speaker: MockResponseSpeaking!
    var viewModel: VoiceChatViewModel!
    var coordinator: VoiceChatCoordinator!

    override func setUp() {
        super.setUp()
        voiceEngine = MockVoiceEngine()
        gateway = MockGatewayConnecting()
        speaker = MockResponseSpeaking()
        viewModel = VoiceChatViewModel()
        coordinator = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker
        )
    }

    // MARK: - Start/Stop Session

    func testStartSessionBeginsListeningAndConnects() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled)
        XCTAssertEqual(gateway.connectURL, url)
    }

    func testStartSessionTransitionsViewModelToListening() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.state, .listening)
    }

    func testStopSessionStopsListeningAndDisconnects() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopSession()

        XCTAssertTrue(voiceEngine.stopListeningCalled)
    }

    func testStopSessionTransitionsViewModelToIdle() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        coordinator.stopSession()

        XCTAssertEqual(viewModel.state, .idle)
    }

    // MARK: - Utterance → Gateway Transcript

    func testUtteranceCompleteSendsTranscriptToGateway() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        // Simulate voice engine completing an utterance
        voiceEngine.onUtteranceComplete?("Hello world")

        // Allow async send to complete
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(gateway.sentTranscripts.count, 1)
        XCTAssertEqual(gateway.sentTranscripts[0].text, "Hello world")
    }

    func testUtteranceCompleteUpdatesViewModelToProcessing() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("Hello world")

        XCTAssertEqual(viewModel.state, .processing)
    }

    func testUtteranceCompleteAddsUserEntryToLog() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("Hello world")

        XCTAssertEqual(viewModel.conversationLog.count, 1)
        XCTAssertEqual(viewModel.conversationLog[0].role, .user)
        XCTAssertEqual(viewModel.conversationLog[0].text, "Hello world")
    }

    // MARK: - Gateway chat.event → ResponseSpeaker

    func testChatEventTokenRouteToSpeaker() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        gateway.simulateEvent("chat.event", payload: [
            "type": "token",
            "text": "Hi there"
        ])

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(speaker.bufferedTokens, ["Hi there"])
    }

    func testChatEventTokenUpdatesViewModelResponseText() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Put VM in processing state first
        viewModel.handleUtteranceComplete("test")

        gateway.simulateEvent("chat.event", payload: [
            "type": "token",
            "text": "Hi "
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        gateway.simulateEvent("chat.event", payload: [
            "type": "token",
            "text": "there"
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.responseText, "Hi there")
        XCTAssertEqual(viewModel.state, .speaking)
    }

    func testChatEventDoneFlushesAndCompletesResponse() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        viewModel.handleUtteranceComplete("test")
        viewModel.handleResponseToken("Response text")

        gateway.simulateEvent("chat.event", payload: [
            "type": "done"
        ])

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(speaker.flushCalled)
        XCTAssertEqual(viewModel.state, .idle)
    }

    // MARK: - Interrupt: User speaks while TTS playing

    func testUserSpeakingWhileSpeakingInterruptsSpeaker() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        // Simulate speaking state
        viewModel.handleUtteranceComplete("test")
        viewModel.handleResponseToken("Hi")
        speaker.state = .speaking

        // User starts talking again (new utterance while speaking)
        voiceEngine.onUtteranceComplete?("Actually wait")

        XCTAssertTrue(speaker.interruptCalled)
    }

    // MARK: - Session Key

    func testSessionKeyIsConsistentWithinSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("First")
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Second")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(gateway.sentTranscripts.count, 2)
        XCTAssertEqual(gateway.sentTranscripts[0].sessionKey, gateway.sentTranscripts[1].sessionKey)
        XCTAssertFalse(gateway.sentTranscripts[0].sessionKey.isEmpty)
    }

    func testNewSessionGetsNewSessionKey() async throws {
        let url = URL(string: "wss://gateway.local:18789")!

        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        voiceEngine.onUtteranceComplete?("First")
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.stopSession()

        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        voiceEngine.onUtteranceComplete?("Second")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(gateway.sentTranscripts.count, 2)
        XCTAssertNotEqual(gateway.sentTranscripts[0].sessionKey, gateway.sentTranscripts[1].sessionKey)
    }

    // MARK: - Stop Session Stops Speaking

    func testStopSessionPreventsIncomingResponseFromSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:test")
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopSession()

        speaker.bufferedTokens = []
        speaker.flushCalled = false

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:test",
            "state": "final",
            "message": ["content": [["text": "Hi there!"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(speaker.bufferedTokens.isEmpty, "Speaker should not buffer tokens after session stopped")
        XCTAssertFalse(speaker.flushCalled, "Speaker should not flush after session stopped")
    }

    func testStopSessionPreventsLegacyTokensFromSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        coordinator.stopSession()

        speaker.bufferedTokens = []
        speaker.flushCalled = false

        gateway.simulateEvent("chat.event", payload: [
            "type": "token",
            "text": "Late response"
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(speaker.bufferedTokens.isEmpty, "Speaker should not buffer legacy tokens after session stopped")

        gateway.simulateEvent("chat.event", payload: [
            "type": "done"
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(speaker.flushCalled, "Speaker should not flush legacy done after session stopped")
    }

    // MARK: - Gateway Delegate

    func testGatewayDelegateIsSetOnInit() {
        // The coordinator should set itself as the gateway's delegate
        XCTAssertNotNil(gateway.delegate)
    }

    // MARK: - Session Key Filtering

    func testChatEventMatchingSessionKeyIsProcessed() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("test")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:abc",
            "state": "delta",
            "message": ["content": [["text": "Hello from correct session"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.responseText, "Hello from correct session")
    }

    func testChatEventDifferentSessionKeyIsIgnored() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("test")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "state": "delta",
            "message": ["content": [["text": "Message from Discord"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotEqual(viewModel.responseText, "Message from Discord")
    }

    func testChatEventWithNoSessionKeyIsIgnored() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("test")

        gateway.simulateEvent("chat", payload: [
            "state": "delta",
            "message": ["content": [["text": "No session key message"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotEqual(viewModel.responseText, "No session key message")
    }

    func testChatFinalEventDifferentSessionKeyDoesNotSpeak() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        speaker.bufferedTokens = []
        speaker.flushCalled = false

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "state": "final",
            "message": ["content": [["text": "Wrong session response"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(speaker.bufferedTokens.isEmpty)
        XCTAssertFalse(speaker.flushCalled)
    }

    func testLegacyTokenEventWithDifferentSessionKeyIsIgnored() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        speaker.bufferedTokens = []

        gateway.simulateEvent("chat.event", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "type": "token",
            "text": "Wrong session token"
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(speaker.bufferedTokens.isEmpty)
    }

    // MARK: - Challenge Failed → Needs Re-pairing

    func testChallengeFailedSendsNeedsRepairing() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        var repairingReceived = false
        let cancellable = coordinator.needsRepairingPublisher.sink {
            repairingReceived = true
        }

        gateway.simulateError(.challengeFailed("pairing_required"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(repairingReceived)
        _ = cancellable
    }

    func testNotPairedErrorSendsNeedsRepairing() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        var repairingReceived = false
        let cancellable = coordinator.needsRepairingPublisher.sink {
            repairingReceived = true
        }

        gateway.simulateError(.challengeFailed("pairing_required:abc123"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(repairingReceived)
        _ = cancellable
    }
}

// MARK: - Echo Cancellation (mic muting while TTS speaks)

extension VoiceChatCoordinatorTests {

    func testMicStopsWhenSpeakerStartsSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.stopListeningCalled = false

        // Simulate speaker transitioning to speaking
        speaker.onStateChange?(.speaking)

        XCTAssertTrue(voiceEngine.stopListeningCalled,
                      "Voice engine should stop listening when speaker starts speaking")
    }

    func testMicDoesNotResumeWhenSpeakerFinishes() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Speaker starts then stops
        speaker.onStateChange?(.speaking)
        voiceEngine.startListeningCalled = false

        speaker.onStateChange?(.idle)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Voice engine should NOT auto-resume after speaker finishes (push-to-talk)")
    }

    func testMicNotResumedAfterSessionStopped() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.stopSession()
        voiceEngine.startListeningCalled = false

        // Speaker finishes after session was stopped
        speaker.onStateChange?(.idle)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Voice engine should NOT resume listening after session stopped")
    }

    func testChatFinalDoesNotRestartMic() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:ptt")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("test")
        viewModel.handleResponseToken("Response")
        voiceEngine.startListeningCalled = false

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:ptt",
            "state": "final",
            "message": ["content": [["text": "Hello!"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Mic should NOT auto-restart after chat final (push-to-talk)")
        XCTAssertEqual(viewModel.state, .idle)
    }

}
