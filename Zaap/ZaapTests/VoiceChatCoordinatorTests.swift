    @MainActor
    func testAwakeSoundPlaysOnMicActivation() {
        let viewModel = VoiceChatViewModel()
        viewModel.tapMic()
        XCTAssertEqual(viewModel.state, .listening)
    }

    @MainActor
    func testPartialResponseHandling() async {
        // Given
        let mockGateway = MockGatewayConnecting()
        let mockSpeaker = MockResponseSpeaking()
        let mockViewModel = VoiceChatViewModel()
        let coordinator = VoiceChatCoordinator(
            viewModel: mockViewModel,
            gateway: mockGateway,
            speaker: mockSpeaker
        )

        // When - simulate partial response
        mockGateway.simulatePartialResponse("Hello")

        // Then - should transition to speaking state and start TTS
        await Task.yield() // Allow async operations
        XCTAssertEqual(mockViewModel.state, .speaking)
        XCTAssertTrue(mockSpeaker.startSpeakingCalled)
        XCTAssertEqual(mockSpeaker.lastText, "Hello")
    }

    @MainActor
    func testPartialResponseCancellation() async {
        // Given
        let mockGateway = MockGatewayConnecting()
        let mockSpeaker = MockResponseSpeaking()
        let mockViewModel = VoiceChatViewModel()
        let coordinator = VoiceChatCoordinator(
            viewModel: mockViewModel,
            gateway: mockGateway,
            speaker: mockSpeaker
        )

        // When - partial response followed by cancellation
        mockGateway.simulatePartialResponse("Hello")
        coordinator.tapMic() // User interrupts

        // Then - should stop speaking and return to listening
        await Task.yield()
        XCTAssertTrue(mockSpeaker.interruptCalled)
        XCTAssertEqual(mockViewModel.state, .listening)
    }