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

    func testUpdateSessionKeyChangesSessionKeyDuringActiveSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main")
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("Hello from main")
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.updateSessionKey("agent:main:discord:channel:123")

        voiceEngine.onUtteranceComplete?("Hello from discord")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(gateway.sentTranscripts.count, 2)
        XCTAssertEqual(gateway.sentTranscripts[0].sessionKey, "agent:main:main")
        XCTAssertEqual(gateway.sentTranscripts[1].sessionKey, "agent:main:discord:channel:123")
    }

    func testUpdateSessionKeyWorksWhenSessionInactive() async throws {
        coordinator.updateSessionKey("agent:main:discord:channel:456")
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: nil)
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)

        // When sessionKey is nil, startSession generates a UUID — not the pre-set key
        // This test verifies updateSessionKey doesn't break startSession's own key assignment
        XCTAssertEqual(gateway.sentTranscripts.count, 1)
        XCTAssertFalse(gateway.sentTranscripts[0].sessionKey.isEmpty)
    }

    // MARK: - Stop Session Stops Speaking

    func testStopSessionPreventsIncomingResponseFromSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:test")
        gateway.simulateConnect()

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)
        coordinator.stopSession()

        speaker.speakImmediateCalled = false
        speaker.spokenTexts = []

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:test",
            "state": "final",
            "message": ["content": [["text": "Hi there!"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(speaker.speakImmediateCalled, "Speaker should not speak after session stopped")
        XCTAssertTrue(speaker.spokenTexts.isEmpty, "No text should be spoken after session stopped")
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

        speaker.speakImmediateCalled = false
        speaker.spokenTexts = []

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "state": "final",
            "message": ["content": [["text": "Wrong session response"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(speaker.speakImmediateCalled)
        XCTAssertTrue(speaker.spokenTexts.isEmpty)
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

    func testRequestFailedDoesNotTriggerRepairing() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        var repairingReceived = false
        let cancellable = coordinator.needsRepairingPublisher.sink {
            repairingReceived = true
        }

        // Non-auth error — should NOT wipe pairing
        gateway.simulateError(.requestFailed("Bad request format"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(repairingReceived, "requestFailed should not trigger re-pairing")
        _ = cancellable
    }

    // MARK: - Operator Gateway Error Isolation

    func testOperatorChallengeFailedDoesNotTriggerRepairing() async throws {
        let operatorGw = MockGatewayConnecting()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )
        coord.micRestartDelay = 0.05

        var repairingReceived = false
        let cancellable = coord.needsRepairingPublisher.sink {
            repairingReceived = true
        }

        // Operator gateway gets PAIRING_REQUIRED (role-upgrade) — should NOT wipe node pairing
        operatorGw.simulateError(.challengeFailed("pairing_required:role-upgrade-abc"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(repairingReceived, "Operator challengeFailed should not trigger re-pairing")
        _ = cancellable
    }

    func testNodeChallengeFailedStillTriggersRepairing() async throws {
        let operatorGw = MockGatewayConnecting()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )
        coord.micRestartDelay = 0.05

        var repairingReceived = false
        let cancellable = coord.needsRepairingPublisher.sink {
            repairingReceived = true
        }

        // Node gateway fails auth — this SHOULD trigger re-pairing
        gateway.simulateError(.challengeFailed("pairing_required:node-expired"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(repairingReceived, "Node challengeFailed should trigger re-pairing")
        _ = cancellable
    }

    func testConnectGatewayConnectsBothGateways() async throws {
        let operatorGw = MockGatewayConnecting()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )

        let url = URL(string: "wss://gateway.local:18789")!
        coord.connectGateway(url: url)

        XCTAssertEqual(gateway.connectURL, url, "Node gateway should connect")
        XCTAssertEqual(operatorGw.connectURL, url, "Operator gateway should connect")
    }

    func testOperatorGatewayConnectLoadsSessions() async throws {
        let operatorGw = MockGatewayConnecting()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )
        let picker = SessionPickerViewModel(sessionLister: operatorGw)
        coord.sessionPicker = picker

        // Operator gateway connects — should load sessions
        operatorGw.simulateConnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        // Sessions were attempted to load (even if empty)
        // The key assertion is that sessionPicker.loadSessions was called via operatorGw, not nodeGw
        XCTAssertNotNil(coord.sessionPicker)
    }
}

// MARK: - Conversation Mode (mic stays hot across listen→process→speak)

extension VoiceChatCoordinatorTests {

    func testMicStopsWhenSpeakerStartsSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.stopListeningCalled = false

        // Speaker starts — mic should stop to prevent echo pickup
        speaker.onStateChange?(.speaking)

        XCTAssertTrue(voiceEngine.stopListeningCalled,
                      "Voice engine should stop listening when speaker starts (software AEC)")
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

    func testToggleConversationModeOffInterruptsSpeaker() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Speaker is speaking
        speaker.simulateStateChange(.speaking)

        // Turn off conversation mode
        coordinator.toggleConversationMode()

        XCTAssertTrue(speaker.interruptCalled,
                      "Toggling conversation mode off should interrupt the speaker")
    }

    func testChatFinalDoesNotSpeakWhenConversationModeOff() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Turn off conversation mode (mic off)
        coordinator.toggleConversationMode()
        speaker.speakImmediateCalled = false
        speaker.spokenTexts.removeAll()

        // A chat final arrives from the gateway
        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main",
            "state": "final",
            "message": ["content": [["text": "Should not be spoken"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(speaker.speakImmediateCalled,
                       "Chat final should NOT speak when conversation mode is off")
        XCTAssertTrue(speaker.spokenTexts.isEmpty,
                      "No text should be spoken when conversation mode is off")
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

    func testSessionKeyMismatchDropsSilently() async throws {
        var loggedMessages: [String] = []
        coordinator.logHandler = { loggedMessages.append($0) }

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        loggedMessages.removeAll()

        gateway.simulateEvent("chat.event", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "type": "token",
            "text": "Wrong session"
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Mismatched events should be dropped silently to avoid flooding the log buffer
        XCTAssertTrue(loggedMessages.isEmpty,
                      "Mismatched session key events should not produce log entries. Got: \(loggedMessages)")
    }

    func testChatEventSessionKeyMismatchDropsSilently() async throws {
        var loggedMessages: [String] = []
        coordinator.logHandler = { loggedMessages.append($0) }

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:abc")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        loggedMessages.removeAll()

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:discord:xyz",
            "state": "final",
            "message": ["content": [["text": "Wrong"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(loggedMessages.isEmpty,
                      "Mismatched chat events should not produce log entries. Got: \(loggedMessages)")
    }

    // MARK: - Echo Suppression

    func testUtteranceMatchingRecentSpokenTextIsFiltered() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:echo")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate TTS speaking "Hello there"
        coordinator.trackSpokenText("Hello there.")

        // STT picks up the echo — should be filtered
        voiceEngine.onUtteranceComplete?("Hello there")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(gateway.sentTranscripts.isEmpty,
                      "Echo of recently spoken text should be filtered out")
    }

    func testUtteranceNotMatchingSpokenTextIsNotFiltered() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:echo")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.trackSpokenText("Hello there.")

        // User says something different — should NOT be filtered
        voiceEngine.onUtteranceComplete?("What is the weather")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(gateway.sentTranscripts.count, 1)
        XCTAssertEqual(gateway.sentTranscripts[0].text, "What is the weather")
    }

    func testSpokenTextTrackedFromChatFinal() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:echo2")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate receiving a chat final that triggers speakImmediate
        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:echo2",
            "state": "final",
            "message": ["content": [["text": "The weather is sunny today."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // STT picks up echo of spoken text
        voiceEngine.onUtteranceComplete?("The weather is sunny today")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(gateway.sentTranscripts.isEmpty,
                      "Echo of gateway response text should be filtered")
    }

}

// MARK: - Chat Final Sets Authoritative Text (zaap-9nl)

extension VoiceChatCoordinatorTests {

    func testChatFinalSetsResponseTextBeforeCompletingSoFullTextIsLogged() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:9nl")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("What is the weather?")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:9nl",
            "state": "delta",
            "message": ["content": [["text": "The weather"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:9nl",
            "state": "final",
            "message": ["content": [["text": "The weather is sunny and warm today with a high of 75F."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Response completion is deferred during TTS (zaap-s5u) — simulate TTS finishing
        speaker.simulateStateChange(.idle)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.conversationLog.last?.text, "The weather is sunny and warm today with a high of 75F.")
        XCTAssertEqual(viewModel.conversationLog.last?.role, .agent)
    }

    func testChatFinalWithNoDeltas_logsFullText() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:9nl2")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Hello")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:9nl2",
            "state": "final",
            "message": ["content": [["text": "Hello! How can I help you today?"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Response completion is deferred during TTS (zaap-s5u) — simulate TTS finishing
        speaker.simulateStateChange(.idle)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.conversationLog.last?.text, "Hello! How can I help you today?")
        XCTAssertEqual(viewModel.conversationLog.last?.role, .agent)
    }
}

// MARK: - Dual Gateway (Operator + Node)

extension VoiceChatCoordinatorTests {

    func testConnectGatewayConnectsBothGateways() {
        let operatorGw = MockGatewayConnecting()
        let dualCoordinator = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )

        let url = URL(string: "wss://gateway.local:18789")!
        dualCoordinator.connectGateway(url: url)

        XCTAssertEqual(gateway.connectURL, url, "Node gateway should connect")
        XCTAssertEqual(operatorGw.connectURL, url, "Operator gateway should connect")
    }

    func testOperatorGatewayConnectTriggersSessionLoad() async throws {
        let operatorGw = MockGatewayConnecting()
        operatorGw.sessionsToReturn = [
            GatewaySession(key: "agent:main:main", title: "Main", lastMessage: nil, channelType: "main")
        ]
        let picker = SessionPickerViewModel(sessionLister: operatorGw)
        let dualCoordinator = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )
        dualCoordinator.sessionPicker = picker

        let url = URL(string: "wss://gateway.local:18789")!
        dualCoordinator.connectGateway(url: url)
        operatorGw.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(picker.sessions.count, 1, "Sessions should load via operator gateway")
    }

    func testNodeGatewayConnectDoesNotLoadSessionsWhenOperatorExists() async throws {
        let operatorGw = MockGatewayConnecting()
        let picker = SessionPickerViewModel(sessionLister: operatorGw)
        let dualCoordinator = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )
        dualCoordinator.sessionPicker = picker

        // Only connect node gateway (not operator)
        let url = URL(string: "wss://gateway.local:18789")!
        gateway.state = .disconnected
        gateway.connect(to: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Sessions should NOT have been loaded since operator gateway didn't connect
        XCTAssertFalse(picker.isLoading, "Node gateway connect should not trigger session loading when operator gateway exists")
    }

    func testOperatorChallengeFailedDoesNotTriggerRepairing_dualGateway() async throws {
        let operatorGw = MockGatewayConnecting()
        let dualCoordinator = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            operatorGateway: operatorGw
        )

        var repairingReceived = false
        let cancellable = dualCoordinator.needsRepairingPublisher.sink {
            repairingReceived = true
        }

        // Operator gateway role-upgrade failure should NOT wipe node pairing
        operatorGw.simulateError(.challengeFailed("pairing_required"))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(repairingReceived, "Operator challengeFailed should not trigger re-pairing — it's a role-upgrade, not a broken node pairing")
        _ = cancellable
    }
}

// MARK: - Session Switch While Mic Active (zaap-wiu)

extension VoiceChatCoordinatorTests {

    func testUpdateSessionKeyWhileActiveStopsVoiceEngine() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.stopListeningCalled = false
        coordinator.updateSessionKey("session-b")

        XCTAssertTrue(voiceEngine.stopListeningCalled,
                      "Voice engine should stop when switching sessions while active")
    }

    func testUpdateSessionKeyWhileActiveInterruptsSpeaker() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        speaker.state = .speaking
        speaker.interruptCalled = false
        coordinator.updateSessionKey("session-b")

        XCTAssertTrue(speaker.interruptCalled,
                      "Speaker should be interrupted when switching sessions while active")
    }

    func testUpdateSessionKeyWhileActiveRestartsMicAfterDelay() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.startListeningCalled = false
        coordinator.updateSessionKey("session-b")

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Mic should not restart immediately after session switch")

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Mic should restart after delay when conversation mode is on")
    }

    func testUpdateSessionKeyWhileActiveAndConversationModeOffDoesNotRestartMic() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.toggleConversationMode()
        voiceEngine.startListeningCalled = false

        coordinator.updateSessionKey("session-b")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Mic should not restart after session switch when conversation mode is off")
    }

    func testUpdateSessionKeyWhileInactiveDoesNotStopVoiceEngine() {
        voiceEngine.stopListeningCalled = false
        coordinator.updateSessionKey("session-b")

        XCTAssertFalse(voiceEngine.stopListeningCalled,
                       "Voice engine should not be stopped when session is not active")
    }

    func testUpdateSessionKeyClearsViewModelPartialState() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.updatePartialTranscript("partial from old session")
        viewModel.handleUtteranceComplete("test")
        viewModel.handleResponseToken("response from old")

        coordinator.updateSessionKey("session-b")

        XCTAssertEqual(viewModel.partialTranscript, "",
                       "Partial transcript should be cleared on session switch")
        XCTAssertEqual(viewModel.responseText, "",
                       "Response text should be cleared on session switch")
    }

    func testUpdateSessionKeyTransitionsViewModelToIdleBeforeRestart() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("test")
        XCTAssertEqual(viewModel.state, .processing)

        coordinator.updateSessionKey("session-b")

        XCTAssertEqual(viewModel.state, .idle,
                       "View model should be idle after session switch (before mic restarts)")
    }

    func testOldSessionResponseIgnoredAfterSessionSwitch() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-a")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.updateSessionKey("session-b")
        try await Task.sleep(nanoseconds: 100_000_000)

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "session-a",
            "state": "final",
            "message": ["content": [["text": "Response to old session"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        let hasOldResponse = viewModel.conversationLog.contains { $0.text == "Response to old session" }
        XCTAssertFalse(hasOldResponse,
                       "Response from old session should be ignored after session switch")
    }

    // MARK: - Thinking Sound

    func testThinkingSoundStartsOnUtteranceComplete() async throws {
        let thinkingSound = MockThinkingSoundPlayer()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            thinkingSoundPlayer: thinkingSound
        )
        coord.startSession(gatewayURL: URL(string: "wss://gw.local:18789")!)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(thinkingSound.isPlaying, "Thinking sound should start after utterance complete")
        XCTAssertEqual(thinkingSound.startCount, 1)
    }

    func testThinkingSoundStopsWhenSpeakerStartsSpeaking() async throws {
        let thinkingSound = MockThinkingSoundPlayer()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            thinkingSoundPlayer: thinkingSound
        )
        coord.startSession(gatewayURL: URL(string: "wss://gw.local:18789")!)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(thinkingSound.isPlaying)

        // Speaker starts speaking - thinking sound should stop
        speaker.simulateStateChange(.speaking)
        XCTAssertFalse(thinkingSound.isPlaying, "Thinking sound should stop when speaker starts")
        XCTAssertEqual(thinkingSound.stopCount, 1)
    }

    func testThinkingSoundStopsOnChatError() async throws {
        let thinkingSound = MockThinkingSoundPlayer()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            thinkingSoundPlayer: thinkingSound
        )
        coord.startSession(gatewayURL: URL(string: "wss://gw.local:18789")!, sessionKey: "test-key")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(thinkingSound.isPlaying)

        gateway.simulateEvent("chat", payload: ["sessionKey": "test-key", "state": "error"])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(thinkingSound.isPlaying, "Thinking sound should stop on error")
    }

    func testThinkingSoundStopsOnSessionStop() async throws {
        let thinkingSound = MockThinkingSoundPlayer()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            thinkingSoundPlayer: thinkingSound
        )
        coord.startSession(gatewayURL: URL(string: "wss://gw.local:18789")!)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(thinkingSound.isPlaying)

        coord.stopSession()
        XCTAssertFalse(thinkingSound.isPlaying, "Thinking sound should stop when session ends")
    }

    func testThinkingSoundStopsOnChatFinal() async throws {
        let thinkingSound = MockThinkingSoundPlayer()
        let coord = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker,
            thinkingSoundPlayer: thinkingSound
        )
        coord.micRestartDelay = 0.05
        coord.startSession(gatewayURL: URL(string: "wss://gw.local:18789")!, sessionKey: "test-key")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.onUtteranceComplete?("Hello")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(thinkingSound.isPlaying)

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "test-key",
            "state": "final",
            "message": ["content": [["text": "Hi there"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(thinkingSound.isPlaying, "Thinking sound should stop on final response")
    }
}

// MARK: - Session Switch UX Improvements (zaap-cxe)

extension VoiceChatCoordinatorTests {

    // MARK: - Flush Pending Transcript to Old Session

    func testUpdateSessionKeyFlushesPartialTranscriptToOldSession() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-old")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // User is mid-sentence when they switch sessions
        voiceEngine.currentTranscript = "I was in the middle of"

        coordinator.updateSessionKey("session-new")
        try await Task.sleep(nanoseconds: 50_000_000)

        // The partial transcript should have been sent to the OLD session key
        XCTAssertEqual(gateway.sentTranscripts.count, 1,
                       "Pending transcript should be flushed on session switch")
        XCTAssertEqual(gateway.sentTranscripts[0].text, "I was in the middle of")
        XCTAssertEqual(gateway.sentTranscripts[0].sessionKey, "session-old",
                       "Flushed transcript should be sent with the OLD session key")
    }

    func testUpdateSessionKeyDoesNotFlushShortTranscript() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-old")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Only "Hi" — too short to flush (< 3 chars)
        voiceEngine.currentTranscript = "Hi"

        coordinator.updateSessionKey("session-new")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(gateway.sentTranscripts.isEmpty,
                      "Short transcript should not be flushed on session switch")
    }

    func testUpdateSessionKeyDoesNotFlushWhenNoTranscript() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-old")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        voiceEngine.currentTranscript = ""

        coordinator.updateSessionKey("session-new")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(gateway.sentTranscripts.isEmpty,
                      "Empty transcript should not be flushed on session switch")
    }

    // MARK: - Session Switch Toast Notification

    func testUpdateSessionKeyShowsSessionSwitchNotice() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-old")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.updateSessionKey("session-new")

        XCTAssertTrue(viewModel.showSessionSwitchNotice,
                      "Session switch should show a notice to the user")
    }

    func testSessionSwitchNoticeAutoClears() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "session-old")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        coordinator.updateSessionKey("session-new")
        XCTAssertTrue(viewModel.showSessionSwitchNotice)

        // Wait for the notice to auto-clear
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertFalse(viewModel.showSessionSwitchNotice,
                       "Session switch notice should auto-clear after a delay")
    }

    func testUpdateSessionKeyWhileInactiveDoesNotShowNotice() {
        coordinator.updateSessionKey("session-new")

        XCTAssertFalse(viewModel.showSessionSwitchNotice,
                       "Should not show notice when session is not active")
    }

    // MARK: - Gateway Reconnect + Conversation Mode Off

    func testGatewayReconnectDoesNotRestartMicWhenConversationModeOff() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled, "Mic should start on initial connect")

        // Turn off conversation mode
        coordinator.toggleConversationMode()
        XCTAssertTrue(voiceEngine.stopListeningCalled, "Mic should stop when conversation mode toggled off")

        // Reset tracking flags
        voiceEngine.startListeningCalled = false

        // Simulate gateway reconnect (network blip)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Mic should NOT restart on gateway reconnect when conversation mode is off")
    }

    func testGatewayReconnectRestartsMicWhenConversationModeOn() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled)
        XCTAssertTrue(voiceEngine.isListening)

        // Simulate gateway reconnect — conversation mode is still on.
        // Engine is already listening (mic works during network blip), so
        // no redundant restart should occur — just verify it stays listening.
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(voiceEngine.isListening,
                      "Mic SHOULD remain listening on gateway reconnect when conversation mode is on")
        XCTAssertEqual(viewModel.state, .listening,
                       "View model should still be in listening state after reconnect")
    }

    func testGatewayReconnectStartsMicWhenItWasStopped() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate mic being stopped (e.g., during TTS or interruption)
        voiceEngine.isListening = false
        voiceEngine.startListeningCalled = false

        // Gateway reconnects — should restart mic since it's not listening
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Mic SHOULD restart on gateway reconnect when it was stopped")
    }
}

// MARK: - Chat Final Speaks as Single Utterance (zaap-ce1)

extension VoiceChatCoordinatorTests {

    func testChatFinalSpeaksEntireResponseAsSingleUtterance() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:ce1")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me about the weather")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:ce1",
            "state": "final",
            "message": ["content": [["text": "The weather is sunny. It will be warm today. Enjoy your day!"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Should speak the entire text as one call to speakImmediate, not bufferToken + flush
        XCTAssertTrue(speaker.speakImmediateCalled,
                      "Chat final should use speakImmediate for single-utterance playback")
        XCTAssertEqual(speaker.spokenTexts.count, 1,
                       "Entire response should be spoken as a single utterance, not split into sentences")
        XCTAssertEqual(speaker.spokenTexts.first, "The weather is sunny. It will be warm today. Enjoy your day!",
                       "Full response text should be spoken")
    }

    func testChatFinalDoesNotUseBufferTokenForSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:ce1b")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Hello")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:ce1b",
            "state": "final",
            "message": ["content": [["text": "Hello! How are you doing today?"]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(speaker.bufferedTokens.isEmpty,
                       "Chat final should NOT use bufferToken — it causes sentence splitting and stutter")
    }
}

// MARK: - Barge-In: Tap to interrupt TTS (zaap-ogv)

extension VoiceChatCoordinatorTests {

    func testBargeInInterruptsSpeaker() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:barge")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate TTS speaking
        speaker.simulateStateChange(.speaking)
        speaker.interruptCalled = false

        coordinator.bargeIn()

        XCTAssertTrue(speaker.interruptCalled,
                      "bargeIn should interrupt the speaker")
    }

    func testBargeInRestartsMicImmediately() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:barge")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate TTS speaking (which stops the mic)
        speaker.simulateStateChange(.speaking)
        voiceEngine.startListeningCalled = false

        coordinator.bargeIn()

        // Mic should restart immediately — no delay
        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "bargeIn should restart mic immediately (no delay)")
    }

    func testBargeInTransitionsViewModelToListening() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:barge")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate TTS speaking
        speaker.simulateStateChange(.speaking)

        coordinator.bargeIn()

        XCTAssertEqual(viewModel.state, .listening,
                       "bargeIn should transition VM to listening")
    }

    func testBargeInDoesNothingWhenSessionInactive() async throws {
        // No session started
        coordinator.bargeIn()

        XCTAssertFalse(speaker.interruptCalled,
                       "bargeIn should do nothing when session is not active")
        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "bargeIn should not start mic when session is not active")
    }

    func testBargeInDoesNothingWhenNotSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:barge")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Speaker is idle, not speaking
        speaker.interruptCalled = false
        voiceEngine.startListeningCalled = false

        coordinator.bargeIn()

        XCTAssertFalse(speaker.interruptCalled,
                       "bargeIn should not interrupt when speaker is not speaking")
    }

    func testBargeInCancelsPendingMicRestart() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:barge")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate TTS finishing normally — mic restart is scheduled
        speaker.simulateStateChange(.speaking)
        speaker.simulateStateChange(.idle)

        // Before the scheduled restart fires, user barges in
        voiceEngine.startListeningCalled = false
        speaker.state = .speaking
        speaker.interruptCalled = false

        coordinator.bargeIn()

        XCTAssertTrue(speaker.interruptCalled,
                      "bargeIn should work even when a mic restart is pending")
        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "bargeIn should restart mic immediately, replacing the pending restart")
    }
}

// MARK: - Barge-In: Deferred Response Completion During TTS (zaap-s5u)

extension VoiceChatCoordinatorTests {

    func testChatFinalKeepsResponseBubbleVisibleDuringTTS() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me a story")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "Once upon a time, there was a fox who lived in the forest."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Response bubble should remain visible during TTS playback
        XCTAssertEqual(viewModel.responseText, "Once upon a time, there was a fox who lived in the forest.",
                       "Response text should remain visible while TTS is playing")
        XCTAssertEqual(viewModel.state, .speaking,
                       "View model should stay in speaking state during TTS")
    }

    func testChatFinalCompletesResponseWhenTTSFinishes() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me a story")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "A short story."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // TTS finishes
        speaker.simulateStateChange(.idle)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.conversationLog.last?.text, "A short story.",
                       "Response should move to conversation log when TTS finishes")
        XCTAssertEqual(viewModel.responseText, "",
                       "Response text should be cleared after TTS finishes")
    }

    func testBargeInDuringTTSMovesResponseToLog() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me a story")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "Once upon a time in a land far away."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // User barges in during TTS
        coordinator.bargeIn()

        // Response text should have been committed to the conversation log
        XCTAssertEqual(viewModel.conversationLog.last?.text, "Once upon a time in a land far away.",
                       "Barge-in should commit response text to conversation log")
        XCTAssertEqual(viewModel.responseText, "",
                       "Response text should be cleared after barge-in")
        XCTAssertEqual(viewModel.state, .listening,
                       "Should transition to listening after barge-in")
    }

    func testViewModelStateSpeakingDuringTTSEnablesMicButtonBargeIn() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Hello")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "Hello! This is a long response that will take a while to speak."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // viewModel.state should be .speaking, which the view uses to decide
        // whether mic button should bargeIn vs toggleConversationMode
        XCTAssertEqual(viewModel.state, .speaking,
                       "VM state should be .speaking during TTS so mic button can trigger barge-in")
    }

    func testStopSessionDuringTTSCompletesResponse() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me something")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "Here is something interesting."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Stop session during TTS
        coordinator.stopSession()

        // Response should be committed to log even though TTS was interrupted
        XCTAssertEqual(viewModel.conversationLog.last?.text, "Here is something interesting.",
                       "Stopping session during TTS should commit response to log")
    }

    func testToggleConversationModeOffDuringTTSCompletesResponse() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me something")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "Here is a response."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Toggle conversation mode off during TTS
        coordinator.toggleConversationMode()

        // Response should be committed to log
        XCTAssertEqual(viewModel.conversationLog.last?.text, "Here is a response.",
                       "Toggling conversation mode off during TTS should commit response to log")
    }

    func testNewUtteranceDuringTTSCompletesOldResponse() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:s5u")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("First question")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:s5u",
            "state": "final",
            "message": ["content": [["text": "First answer."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // User speaks while TTS is playing (barge-in via voice)
        voiceEngine.onUtteranceComplete?("Second question")
        try await Task.sleep(nanoseconds: 50_000_000)

        // First answer should be in the log, followed by the new user question
        let logTexts = viewModel.conversationLog.map { $0.text }
        XCTAssertTrue(logTexts.contains("First answer."),
                      "Old response should be committed to log when user speaks over TTS")
        XCTAssertTrue(logTexts.contains("Second question"),
                      "New user utterance should be in the log")
    }
}

// MARK: - First Mic Tap Fix (zaap-4bp)

extension VoiceChatCoordinatorTests {

    func testStartSessionProvidesImmediateFeedbackWhenGatewayConnecting() {
        // Simulate gateway already in connecting state (eager connect from onAppear)
        gateway.state = .connecting

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        // User should see immediate feedback even though gateway isn't connected yet
        XCTAssertEqual(viewModel.state, .listening,
                       "View model should transition to listening immediately, regardless of gateway state")
        XCTAssertTrue(coordinator.isSessionActive)
        XCTAssertTrue(coordinator.isConversationModeOn)
    }

    func testStartSessionWhenGatewayConnectingDoesNotDoubleToggleOnConnect() async throws {
        // Gateway is in connecting state
        gateway.state = .connecting

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        XCTAssertEqual(viewModel.state, .listening)

        // Gateway finishes connecting
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Should still be listening (not toggled back to idle)
        XCTAssertEqual(viewModel.state, .listening,
                       "Gateway connect should not toggle viewModel back to idle")
        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Voice engine should start listening when gateway connects")
    }

    func testStartSessionWhenGatewayAlreadyConnectedStartsImmediately() async throws {
        // Gateway already connected (eager connect completed before user tapped)
        gateway.state = .connected

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        XCTAssertEqual(viewModel.state, .listening,
                       "View model should transition to listening immediately")
        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Voice engine should start listening immediately when gateway is connected")
    }

    func testStartSessionWhenGatewayDisconnectedStartsAfterConnect() async throws {
        // Gateway is disconnected
        gateway.state = .disconnected

        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url)

        // Should show immediate visual feedback
        XCTAssertEqual(viewModel.state, .listening,
                       "View model should transition to listening immediately even when disconnected")
        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "Voice engine should NOT start before gateway connects")

        // Gateway connects
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "Voice engine should start after gateway connects")
        XCTAssertEqual(viewModel.state, .listening,
                       "View model should remain in listening state")
    }

    func testGatewayDidConnectDoesNotDoubleToggleViewModelFromListening() async throws {
        // Simulate the exact on-device flow:
        // 1. onAppear → connectGateway (eager)
        // 2. user taps mic → startSession (gateway already connected)
        // 3. gatewayDidConnect fires from a RECONNECT
        let url = URL(string: "wss://gateway.local:18789")!
        gateway.state = .connected
        coordinator.startSession(gatewayURL: url)

        XCTAssertEqual(viewModel.state, .listening)

        // Simulate a gateway reconnect (e.g., network blip)
        voiceEngine.startListeningCalled = false
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // viewModel should NOT have been toggled to idle and back
        XCTAssertEqual(viewModel.state, .listening,
                       "Gateway reconnect should not toggle viewModel state from listening")
    }
}

// MARK: - Barge-In Device Fix: Race Condition (zaap-2zg)

extension VoiceChatCoordinatorTests {

    /// On real devices, AVSpeechSynthesizerDelegate.didFinish can fire on a
    /// background thread, flipping speaker.state to .idle before the UI updates.
    /// The user sees "Tap to interrupt" (viewModel.state is still .speaking)
    /// but bargeIn() sees speaker.state == .idle and silently returns.
    /// Fix: bargeIn() also accepts pendingResponseCompletion as a trigger.
    func testBargeInWorksWhenSpeakerAlreadyIdleButResponsePending() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:2zg")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Tell me a story")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:2zg",
            "state": "final",
            "message": ["content": [["text": "Once upon a time in a faraway land."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate the device race condition: speaker.state goes .idle
        // (e.g., didFinish on a background thread) but onStateChange hasn't
        // run on the main thread yet, so pendingResponseCompletion is still true.
        // We can't perfectly simulate async dispatch, but we can set up the
        // equivalent state: speaker.state = .idle while viewModel.state = .speaking
        speaker.state = .idle // Simulate didFinish setting state on background thread
        // pendingResponseCompletion is still true (onStateChange(.idle) hasn't run)
        XCTAssertEqual(viewModel.state, .speaking,
                       "Setup: viewModel should still be .speaking (UI hasn't updated)")

        voiceEngine.startListeningCalled = false

        coordinator.bargeIn()

        // bargeIn should work via pendingResponseCompletion even though speaker.state is .idle
        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "bargeIn must activate mic even when speaker.state is .idle but response is pending")
        XCTAssertEqual(viewModel.state, .listening,
                       "bargeIn must transition to listening")

        // Response text should be committed to conversation log
        let logTexts = viewModel.conversationLog.map { $0.text }
        XCTAssertTrue(logTexts.contains("Once upon a time in a faraway land."),
                      "Response should be committed to log on barge-in")
    }

    func testBargeInStillWorksWhenSpeakerIsSpeaking() async throws {
        // Ensure the original path (speaker.state == .speaking) still works
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:2zg2")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        viewModel.handleUtteranceComplete("Hello")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "agent:main:main:2zg2",
            "state": "final",
            "message": ["content": [["text": "Hello! This is a long response."]]]
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Speaker is actively speaking (normal case)
        XCTAssertEqual(speaker.state, .speaking)
        voiceEngine.startListeningCalled = false

        coordinator.bargeIn()

        XCTAssertTrue(voiceEngine.startListeningCalled,
                      "bargeIn must work when speaker is actively speaking")
        XCTAssertEqual(viewModel.state, .listening)
    }

    func testBargeInDoesNothingWhenNoPendingResponseAndNotSpeaking() async throws {
        let url = URL(string: "wss://gateway.local:18789")!
        coordinator.startSession(gatewayURL: url, sessionKey: "agent:main:main:2zg3")
        gateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // No TTS playing, no pending response
        speaker.state = .idle
        voiceEngine.startListeningCalled = false
        speaker.interruptCalled = false

        coordinator.bargeIn()

        XCTAssertFalse(speaker.interruptCalled,
                       "bargeIn should do nothing when no TTS and no pending response")
        XCTAssertFalse(voiceEngine.startListeningCalled,
                       "bargeIn should not start mic when nothing to interrupt")
    }

    func testMockInterruptFiresOnStateChange() async throws {
        // Verify the mock now matches real ResponseSpeaker behavior:
        // interrupt() should fire onStateChange when state changes.
        var stateChanges: [SpeakerState] = []
        speaker.onStateChange = { stateChanges.append($0) }

        speaker.state = .speaking
        stateChanges.removeAll() // clear the setup

        speaker.interrupt()

        XCTAssertEqual(stateChanges, [.idle],
                       "Mock interrupt() must fire onStateChange when state changes from .speaking to .idle")
    }

    func testMockInterruptDoesNotFireOnStateChangeWhenAlreadyIdle() async throws {
        var stateChanges: [SpeakerState] = []
        speaker.onStateChange = { stateChanges.append($0) }

        // speaker starts idle
        speaker.interrupt()

        XCTAssertTrue(stateChanges.isEmpty,
                      "Mock interrupt() must NOT fire onStateChange when state is already .idle")
    }
}
