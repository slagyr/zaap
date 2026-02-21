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

    func testStartSessionBeginsListeningAndConnects() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        XCTAssertTrue(voiceEngine.startListeningCalled)
        XCTAssertEqual(gateway.connectURL, url)
    }

    func testStartSessionTransitionsViewModelToListening() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        XCTAssertEqual(viewModel.state, .listening)
    }

    func testStopSessionStopsListeningAndDisconnects() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        coordinator.stopSession()

        XCTAssertTrue(voiceEngine.stopListeningCalled)
        XCTAssertTrue(gateway.disconnectCalled)
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
        XCTAssertEqual(viewModel.state, .listening)
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

    // MARK: - Gateway Delegate

    func testGatewayDelegateIsSetOnInit() {
        // The coordinator should set itself as the gateway's delegate
        XCTAssertNotNil(gateway.delegate)
    }
}
