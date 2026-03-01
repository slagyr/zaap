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
        coordinator.micRestartDelay = 0.05 // Short delay for tests (50ms)
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

// MARK: - Conversation Mode (mic stays hot across listen→process→speak)

extension VoiceChatCoordinatorTests {

    func testMicContinuesWhenSpeakerStartsSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.stopListeningCalled = false

        // Speaker starts — mic should NOT stop (trust AEC)
        speaker.onStateChange?(.speaking)

        XCTAssertFalse(voiceEngine.stopListeningCalled,
                       "Voice engine should NOT stop listening when speaker starts (trust AEC)")
    }

    func testMicRestartsWhenSpeakerFinishes() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate full conversation cycle: utterance → response → speaker finishes
        voiceEngine.onUtteranceComplete?("Hello")
        viewModel.handleResponseToken("Hi there")
        viewModel.handleResponseComplete() // → .idle

        voiceEngine.startListeningCalled = false

        // Speaker finishes TTS — should auto-restart mic after delay
        speaker.onStateChange?(.idle)

        // Mic should NOT restart immediately
        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Voice engine should NOT restart immediately — delay required")

        // Wait for the restart delay to elapse
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms > 50ms delay

        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Voice engine should auto-restart after delay when speaker finishes")
        XCTAssertEqual(viewModel.state, .listening,
                       "View model should transition to listening after delayed restart")
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

    func testChatFinalDoesNotDirectlyRestartMic() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:conv")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("test")
        viewModel.handleResponseToken("Response")
        voiceEngine.startListeningCalled = false

        // Chat final arrives but speaker hasn't finished yet
        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:conv",
            "state": "final",
            "message": ["content": [["text": "Hello!"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Chat final should not directly restart mic — only speaker finishing does")
    }

    // MARK: - Tapping Mic Toggles Conversation Mode

    func testTapMicWhileListeningTurnsOffConversationMode() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Session active, conversation mode on, listening
        XCTAssertEqual(viewModel.state, .listening)

        // User taps mic to turn off conversation mode
        coordinator.toggleConversationMode()

        XCTAssertEqual(viewModel.state, .idle,
                       "Tapping mic while listening should transition to idle")
        XCTAssertTrue(voiceEngine.stopListeningCalled,
                      "Tapping mic while listening should stop voice engine")
    }

    func testTapMicWhileIdleTurnsOnConversationMode() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Turn off conversation mode first
        coordinator.toggleConversationMode()
        voiceEngine.startListeningCalled = false

        // Now tap mic again to turn conversation mode back on
        coordinator.toggleConversationMode()

        XCTAssertEqual(viewModel.state, .listening,
                       "Tapping mic while idle should transition to listening")
        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Tapping mic while idle should start voice engine")
    }

    func testConversationModeOffPreventsAutoRestartAfterSpeaker() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Turn off conversation mode
        coordinator.toggleConversationMode()
        voiceEngine.startListeningCalled = false

        // Simulate speaker finishing — should NOT auto-restart mic
        speaker.onStateChange?(.idle)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Speaker finishing should NOT restart mic when conversation mode is off")
    }

    func testConversationModeOnAfterToggleReenablesAutoRestart() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Toggle off then on
        coordinator.toggleConversationMode()
        coordinator.toggleConversationMode()

        // Simulate a full cycle
        voiceEngine.onUtteranceComplete?("Hello")
        viewModel.handleResponseToken("Hi")
        viewModel.handleResponseComplete()
        voiceEngine.startListeningCalled = false

        // Speaker finishes — should auto-restart mic after delay
        speaker.onStateChange?(.idle)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Speaker finishing should restart mic after conversation mode toggled back on")
    }

    // MARK: - Mic Restart Delay

    func testMicRestartDelayCancelledWhenConversationModeToggledOff() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        viewModel.handleResponseToken("Hi")
        viewModel.handleResponseComplete()
        voiceEngine.startListeningCalled = false

        // Speaker finishes — delay starts
        speaker.onStateChange?(.idle)

        // Toggle off conversation mode during the delay
        coordinator.toggleConversationMode()

        // Wait for the delay to elapse
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Mic should NOT restart if conversation mode was toggled off during delay")
    }

    func testMicRestartDelayCancelledWhenSessionStopped() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        viewModel.handleResponseToken("Hi")
        viewModel.handleResponseComplete()
        voiceEngine.startListeningCalled = false

        // Speaker finishes — delay starts
        speaker.onStateChange?(.idle)

        // Stop session during the delay
        coordinator.stopSession()
        voiceEngine.startListeningCalled = false

        // Wait for the delay to elapse
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Mic should NOT restart if session was stopped during delay")
    }

    // MARK: - isConversationModeOn Published Property

    func testIsConversationModeOnStartsFalse() {
        XCTAssertFalse(coordinator.isConversationModeOn,
                       "Conversation mode should be off before session starts")
    }

    func testIsConversationModeOnTrueAfterStartSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(coordinator.isConversationModeOn,
                      "Conversation mode should be on after starting session")
    }

    func testIsConversationModeOnFalseAfterToggleOff() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.toggleConversationMode()

        XCTAssertFalse(coordinator.isConversationModeOn,
                       "Conversation mode should be off after toggling off")
    }

    func testIsConversationModeOnTrueAfterToggleBackOn() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.toggleConversationMode()
        coordinator.toggleConversationMode()

        XCTAssertTrue(coordinator.isConversationModeOn,
                      "Conversation mode should be back on after toggling on again")
    }

    func testIsConversationModeOnFalseAfterStopSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.stopSession()

        XCTAssertFalse(coordinator.isConversationModeOn,
                       "Conversation mode should be off after stopping session")
    }

    // MARK: - isSessionActive Published Property

    func testIsSessionActiveStartsFalse() {
        XCTAssertFalse(coordinator.isSessionActive,
                       "Session should not be active before starting")
    }

    func testIsSessionActiveTrueAfterStartSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(coordinator.isSessionActive,
                      "Session should be active after starting")
    }

    func testIsSessionActiveStillTrueAfterConversationModeToggleOff() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.toggleConversationMode()

        XCTAssertTrue(coordinator.isSessionActive,
                      "Session should remain active when conversation mode toggled off")
    }

    func testIsSessionActiveFalseAfterStopSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.stopSession()

        XCTAssertFalse(coordinator.isSessionActive,
                       "Session should not be active after stopping")
    }

}

// MARK: - Eager Gateway Connection

extension VoiceChatCoordinatorTests {

    func testConnectGatewayConnectsWithoutStartingSession() {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.connectGateway(url: url)

        XCTAssertEqual(gateway.connectURL, url, "Should connect to the provided URL")
        XCTAssertFalse(coordinator.isSessionActive, "Should not start a session")
        XCTAssertFalse(coordinator.isConversationModeOn, "Should not enable conversation mode")
        XCTAssertFalse(voiceEngine.startListeningCalled, "Should not start voice engine")
    }

    func testConnectGatewayTriggersSessionLoad() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        let picker = SessionPickerViewModel(sessionLister: gateway)
        coordinator.sessionPicker = picker
        gateway.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main"),
            GatewaySession(key: "agent:main:discord:abc", title: "Discord", lastMessage: nil, channelType: "discord")
        ]

        coordinator.connectGateway(url: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(picker.sessions.count, 2, "Sessions should be loaded after eager connect")
        XCTAssertFalse(coordinator.isSessionActive, "Session should not be active after eager connect")
        XCTAssertFalse(voiceEngine.startListeningCalled, "Mic should not start after eager connect")
    }

    func testConnectGatewaySkipsIfAlreadyConnected() {
        let url = URL(string: "wss://gateway.local:18789")!
        gateway.state = .connected

        coordinator.connectGateway(url: url)

        XCTAssertNil(gateway.connectURL, "Should not call connect when already connected")
    }

    func testConnectGatewaySkipsIfAlreadyConnecting() {
        let url = URL(string: "wss://gateway.local:18789")!
        gateway.state = .connecting

        coordinator.connectGateway(url: url)

        XCTAssertNil(gateway.connectURL, "Should not call connect when already connecting")
    }
}

// MARK: - Gateway Event Logging

extension VoiceChatCoordinatorTests {

    func testLogsRawPayloadOnGatewayEvent() async throws {
        var loggedMessages: [String] = []
        coordinator.logHandler = { loggedMessages.append($0) }

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:log")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:log",
            "state": "delta",
            "message": ["content": [["text": "Hello"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasRawPayload = loggedMessages.contains { $0.contains("[VOICE]") && $0.contains("event=chat") }
        XCTAssertTrue(hasRawPayload, "Should log raw event info. Got: \(loggedMessages)")
    }

    func testLogsWhenTextExtractionReturnsNil() async throws {
        var loggedMessages: [String] = []
        coordinator.logHandler = { loggedMessages.append($0) }

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:log")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Send chat event with malformed message — no text field
        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:log",
            "state": "delta",
            "message": ["content": [["type": "image"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasNilTextLog = loggedMessages.contains { $0.contains("text extraction returned nil") }
        XCTAssertTrue(hasNilTextLog, "Should log when text extraction returns nil. Got: \(loggedMessages)")
    }

    func testLogsWhenSessionKeyMismatchDropsEvent() async throws {
        var loggedMessages: [String] = []
        coordinator.logHandler = { loggedMessages.append($0) }

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        gateway.simulateEvent("chat.event", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "type": "token",
            "text": "Wrong session"
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasDropLog = loggedMessages.contains { $0.contains("dropping") && $0.contains("session key mismatch") }
        XCTAssertTrue(hasDropLog, "Should log when event dropped due to session key mismatch. Got: \(loggedMessages)")
    }

    func testLogsWhenChatEventSessionKeyMismatchDropsEvent() async throws {
        var loggedMessages: [String] = []
        coordinator.logHandler = { loggedMessages.append($0) }

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "state": "final",
            "message": ["content": [["text": "Wrong"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasDropLog = loggedMessages.contains { $0.contains("dropping") && $0.contains("session key") }
        XCTAssertTrue(hasDropLog, "Should log when chat event dropped due to session key mismatch. Got: \(loggedMessages)")
    }
}
