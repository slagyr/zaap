import XCTest
@testable import Zaap

@MainActor
final class VoiceChatCoordinatorTests: XCTestCase {

    private func makeCoordinator() -> (
        coordinator: VoiceChatCoordinator,
        viewModel: VoiceChatViewModel,
        voiceEngine: MockVoiceEngine,
        gateway: MockGatewayConnecting,
        speaker: MockResponseSpeaking
    ) {
        let viewModel = VoiceChatViewModel()
        let voiceEngine = MockVoiceEngine()
        let gateway = MockGatewayConnecting()
        let speaker = MockResponseSpeaking()
        let coordinator = VoiceChatCoordinator(
            viewModel: viewModel,
            voiceEngine: voiceEngine,
            gateway: gateway,
            speaker: speaker
        )
        return (coordinator, viewModel, voiceEngine, gateway, speaker)
    }

    func testStartSessionWhileConnectedStartsListening() {
        let (coordinator, viewModel, voiceEngine, gateway, _) = makeCoordinator()
        gateway.state = .connected

        coordinator.startSession(gatewayURL: URL(string: "https://example.com")!, sessionKey: "signal-loft")

        XCTAssertTrue(voiceEngine.startListeningCalled)
        XCTAssertEqual(viewModel.state, .listening)
    }

    func testChatFinalEventSpeaksResponseForActiveSession() async {
        let (coordinator, viewModel, _, gateway, speaker) = makeCoordinator()
        gateway.state = .connected
        coordinator.startSession(gatewayURL: URL(string: "https://example.com")!, sessionKey: "signal-loft")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "signal-loft",
            "state": "final",
            "message": [
                "content": [
                    ["text": "Hello from the harbor"]
                ]
            ]
        ])
        await Task.yield()

        XCTAssertTrue(speaker.speakImmediateCalled)
        XCTAssertEqual(speaker.spokenTexts, ["Hello from the harbor"])
        XCTAssertEqual(viewModel.responseText, "Hello from the harbor")
    }

    func testBargeInInterruptsSpeakerAndReturnsToListening() async {
        let (coordinator, viewModel, voiceEngine, gateway, speaker) = makeCoordinator()
        gateway.state = .connected
        coordinator.startSession(gatewayURL: URL(string: "https://example.com")!, sessionKey: "signal-loft")

        gateway.simulateEvent("chat", payload: [
            "sessionKey": "signal-loft",
            "state": "final",
            "message": [
                "content": [
                    ["text": "Hello from the harbor"]
                ]
            ]
        ])
        await Task.yield()
        voiceEngine.startListeningCalled = false

        coordinator.bargeIn()

        XCTAssertTrue(speaker.interruptCalled)
        XCTAssertTrue(voiceEngine.startListeningCalled)
        XCTAssertEqual(viewModel.state, .listening)
    }
}
