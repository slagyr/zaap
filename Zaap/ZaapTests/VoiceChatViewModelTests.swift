import XCTest
@testable import Zaap

@MainActor
final class VoiceChatViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        let vm = VoiceChatViewModel()
        XCTAssertEqual(vm.state, .idle)
    }

    func testConversationLogStartsEmpty() {
        let vm = VoiceChatViewModel()
        XCTAssertTrue(vm.conversationLog.isEmpty)
    }

    func testPartialTranscriptStartsEmpty() {
        let vm = VoiceChatViewModel()
        XCTAssertEqual(vm.partialTranscript, "")
    }

    func testResponseTextStartsEmpty() {
        let vm = VoiceChatViewModel()
        XCTAssertEqual(vm.responseText, "")
    }

    // MARK: - State Transitions

    func testTapMicTransitionsFromIdleToListening() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        XCTAssertEqual(vm.state, .listening)
    }

    func testTapMicWhileListeningTransitionsToIdle() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.tapMic()
        XCTAssertEqual(vm.state, .idle)
    }

    func testReceiveUtteranceTransitionsToProcessing() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello there")
        XCTAssertEqual(vm.state, .processing)
    }

    func testReceiveUtteranceAddsUserMessageToLog() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello there")
        XCTAssertEqual(vm.conversationLog.count, 1)
        XCTAssertEqual(vm.conversationLog[0].role, .user)
        XCTAssertEqual(vm.conversationLog[0].text, "Hello there")
    }

    func testReceiveUtteranceClearsPartialTranscript() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.updatePartialTranscript("Hell")
        vm.handleUtteranceComplete("Hello there")
        XCTAssertEqual(vm.partialTranscript, "")
    }

    func testReceiveResponseTokenTransitionsToSpeaking() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi")
        XCTAssertEqual(vm.state, .speaking)
    }

    func testReceiveResponseTokenAccumulatesResponseText() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi ")
        vm.handleResponseToken("there")
        XCTAssertEqual(vm.responseText, "Hi there")
    }

    func testResponseCompleteAddsAgentMessageToLog() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi there")
        vm.handleResponseComplete()
        XCTAssertEqual(vm.conversationLog.count, 2)
        XCTAssertEqual(vm.conversationLog[1].role, .agent)
        XCTAssertEqual(vm.conversationLog[1].text, "Hi there")
    }

    func testResponseCompleteTransitionsToIdle() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi there")
        vm.handleResponseComplete()
        XCTAssertEqual(vm.state, .idle)
    }

    func testResponseCompleteClearsResponseText() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi there")
        vm.handleResponseComplete()
        XCTAssertEqual(vm.responseText, "")
    }

    // MARK: - Partial Transcript

    func testUpdatePartialTranscript() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.updatePartialTranscript("Hel")
        XCTAssertEqual(vm.partialTranscript, "Hel")
    }

    // MARK: - Conversation Log

    func testMultipleExchangesBuildUpLog() {
        let vm = VoiceChatViewModel()
        vm.tapMic()

        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi!")
        vm.handleResponseComplete()

        vm.handleUtteranceComplete("How are you?")
        vm.handleResponseToken("I'm great!")
        vm.handleResponseComplete()

        XCTAssertEqual(vm.conversationLog.count, 4)
        XCTAssertEqual(vm.conversationLog[0].role, .user)
        XCTAssertEqual(vm.conversationLog[1].role, .agent)
        XCTAssertEqual(vm.conversationLog[2].role, .user)
        XCTAssertEqual(vm.conversationLog[3].role, .agent)
    }

    // MARK: - Stop While Speaking

    func testTapMicWhileSpeakingTransitionsToIdle() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        vm.handleResponseToken("Hi")
        XCTAssertEqual(vm.state, .speaking)
        vm.tapMic()
        XCTAssertEqual(vm.state, .idle)
    }

    func testTapMicWhileProcessingTransitionsToIdle() {
        let vm = VoiceChatViewModel()
        vm.tapMic()
        vm.handleUtteranceComplete("Hello")
        XCTAssertEqual(vm.state, .processing)
        vm.tapMic()
        XCTAssertEqual(vm.state, .idle)
    }
}
