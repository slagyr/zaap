import AVFoundation
import XCTest
@testable import Zaap

final class ResponseSpeakerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        let speaker = ResponseSpeaker(synthesizer: MockSpeechSynthesizer())
        XCTAssertEqual(speaker.state, .idle)
    }

    // MARK: - Sentence Boundary Detection

    func testExtractSentencesFromBufferWithPeriod() {
        let result = ResponseSpeaker.extractSentences(from: "Hello world. How are you")
        XCTAssertEqual(result.sentences, ["Hello world."])
        XCTAssertEqual(result.remainder, " How are you")
    }

    func testExtractSentencesFromBufferWithMultipleSentences() {
        let result = ResponseSpeaker.extractSentences(from: "First. Second! Third? Leftover")
        XCTAssertEqual(result.sentences, ["First.", " Second!", " Third?"])
        XCTAssertEqual(result.remainder, " Leftover")
    }

    func testExtractSentencesNoCompleteSentence() {
        let result = ResponseSpeaker.extractSentences(from: "Hello world")
        XCTAssertEqual(result.sentences, [])
        XCTAssertEqual(result.remainder, "Hello world")
    }

    func testExtractSentencesEmptyString() {
        let result = ResponseSpeaker.extractSentences(from: "")
        XCTAssertEqual(result.sentences, [])
        XCTAssertEqual(result.remainder, "")
    }

    func testExtractSentencesWithNewlines() {
        let result = ResponseSpeaker.extractSentences(from: "Hello.\nGoodbye.\nMore")
        XCTAssertEqual(result.sentences, ["Hello.", "\nGoodbye."])
        XCTAssertEqual(result.remainder, "\nMore")
    }

    func testExtractSentencesHandlesAbbreviations() {
        // Abbreviation-like patterns (e.g. Mr. Dr.) are tricky.
        // Our simple approach splits on all sentence-ending punctuation.
        // This is acceptable for TTS which handles fragments fine.
        let result = ResponseSpeaker.extractSentences(from: "Hello Mr. Smith. How are you")
        XCTAssertEqual(result.sentences, ["Hello Mr.", " Smith."])
        XCTAssertEqual(result.remainder, " How are you")
    }

    // MARK: - Speaking

    func testSpeakImmediateCallsSynthesizer() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("Hello world")

        XCTAssertEqual(mock.spokenTexts.count, 1)
        XCTAssertEqual(mock.spokenTexts.first, "Hello world")
        XCTAssertEqual(speaker.state, .speaking)
    }

    func testSpeakImmediateTrimsWhitespace() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("  Hello  ")

        XCTAssertEqual(mock.spokenTexts.first, "Hello")
    }

    func testSpeakImmediateIgnoresEmptyString() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("")

        XCTAssertEqual(mock.spokenTexts.count, 0)
        XCTAssertEqual(speaker.state, .idle)
    }

    func testSpeakImmediateIgnoresWhitespaceOnly() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("   ")

        XCTAssertEqual(mock.spokenTexts.count, 0)
        XCTAssertEqual(speaker.state, .idle)
    }

    // MARK: - Interrupt

    func testInterruptStopsSynthesizer() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("Hello world")
        XCTAssertEqual(speaker.state, .speaking)

        speaker.interrupt()

        XCTAssertTrue(mock.stopCalled)
        XCTAssertEqual(speaker.state, .idle)
    }

    func testInterruptWhenIdleIsNoOp() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.interrupt()

        XCTAssertFalse(mock.stopCalled)
        XCTAssertEqual(speaker.state, .idle)
    }

    func testInterruptClearsBuffer() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("Hello")
        speaker.interrupt()

        // After interrupt, buffer should be cleared
        // Flushing should produce nothing
        speaker.flush()
        XCTAssertEqual(mock.spokenTexts.count, 0)
    }

    // MARK: - Token Buffering

    func testBufferTokenAccumulatesText() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("Hello ")
        speaker.bufferToken("world")

        // No sentence boundary yet, so nothing spoken
        XCTAssertEqual(mock.spokenTexts.count, 0)
    }

    func testBufferTokenSpeaksOnSentenceBoundary() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("Hello ")
        speaker.bufferToken("world.")

        XCTAssertEqual(mock.spokenTexts.count, 1)
        XCTAssertEqual(mock.spokenTexts.first, "Hello world.")
        XCTAssertEqual(speaker.state, .speaking)
    }

    func testBufferTokenSpeaksMultipleSentences() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("First. Second!")

        XCTAssertEqual(mock.spokenTexts.count, 2)
        XCTAssertEqual(mock.spokenTexts[0], "First.")
        XCTAssertEqual(mock.spokenTexts[1], "Second!")
    }

    func testBufferTokenKeepsRemainderForNextToken() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("Hello world. Good")
        speaker.bufferToken("bye!")

        XCTAssertEqual(mock.spokenTexts.count, 2)
        XCTAssertEqual(mock.spokenTexts[0], "Hello world.")
        XCTAssertEqual(mock.spokenTexts[1], "Goodbye!")
    }

    // MARK: - Flush

    func testFlushSpeaksRemainingBuffer() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("Hello world")
        XCTAssertEqual(mock.spokenTexts.count, 0)

        speaker.flush()

        XCTAssertEqual(mock.spokenTexts.count, 1)
        XCTAssertEqual(mock.spokenTexts.first, "Hello world")
    }

    func testFlushIgnoresEmptyBuffer() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.flush()

        XCTAssertEqual(mock.spokenTexts.count, 0)
    }

    func testFlushIgnoresWhitespaceBuffer() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("   ")
        speaker.flush()

        XCTAssertEqual(mock.spokenTexts.count, 0)
    }

    // MARK: - Delegate / State Transitions

    func testStateTransitionsToIdleWhenSpeechFinishes() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("Hello")
        XCTAssertEqual(speaker.state, .speaking)

        // Simulate synthesizer finishing
        mock.simulateDidFinish()

        XCTAssertEqual(speaker.state, .idle)
    }

    func testStateRemainsSpeakingWhenQueuedUtterancesRemain() {
        let mock = MockSpeechSynthesizer()
        mock.isSpeakingValue = true
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.speakImmediate("Hello")
        mock.simulateDidFinish()

        // Still speaking because mock says isSpeaking = true (queued utterances)
        XCTAssertEqual(speaker.state, .speaking)
    }

    // MARK: - Question Mark Boundary

    func testBufferTokenSpeaksOnQuestionMark() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("How are you?")

        XCTAssertEqual(mock.spokenTexts.count, 1)
        XCTAssertEqual(mock.spokenTexts.first, "How are you?")
    }

    // MARK: - Exclamation Boundary

    func testBufferTokenSpeaksOnExclamationMark() {
        let mock = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: mock)

        speaker.bufferToken("Wow!")

        XCTAssertEqual(mock.spokenTexts.count, 1)
        XCTAssertEqual(mock.spokenTexts.first, "Wow!")
    }

    // MARK: - Voice from Settings (DI)

    func testSpeakImmediateUsesVoiceIdentifierFromSettings() throws {
        let voiceId = "com.apple.voice.compact.en-US.Samantha"
        let resolvedVoice = AVSpeechSynthesisVoice(identifier: voiceId)
        try XCTSkipUnless(resolvedVoice != nil && resolvedVoice!.identifier == voiceId, "Voice \(voiceId) not installed on this simulator")
        let mock = MockSpeechSynthesizer()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        settings.ttsVoiceIdentifier = voiceId
        let speaker = ResponseSpeaker(synthesizer: mock, settings: settings)

        speaker.speakImmediate("Hello")

        XCTAssertEqual(mock.spokenUtterances.first?.voice?.identifier, voiceId)
    }

    func testSpeakImmediateUsesSystemDefaultWhenVoiceIdentifierEmpty() {
        let mock = MockSpeechSynthesizer()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        settings.ttsVoiceIdentifier = ""
        let speaker = ResponseSpeaker(synthesizer: mock, settings: settings)

        speaker.speakImmediate("Hello")

        XCTAssertEqual(mock.spokenUtterances.first?.voice?.language, "en-US")
    }

    func testSpeakImmediatePicksUpVoiceChangeBetweenCalls() throws {
        let voiceId = "com.apple.voice.compact.en-US.Samantha"
        let resolvedVoice = AVSpeechSynthesisVoice(identifier: voiceId)
        try XCTSkipUnless(resolvedVoice != nil && resolvedVoice!.identifier == voiceId, "Voice \(voiceId) not installed on this simulator")
        let mock = MockSpeechSynthesizer()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        settings.ttsVoiceIdentifier = ""
        let speaker = ResponseSpeaker(synthesizer: mock, settings: settings)

        speaker.speakImmediate("First")
        let firstVoice = mock.spokenUtterances[0].voice

        settings.ttsVoiceIdentifier = voiceId
        speaker.speakImmediate("Second")
        let secondVoice = mock.spokenUtterances[1].voice

        XCTAssertNotEqual(firstVoice?.identifier, secondVoice?.identifier)
    }
}

    // MARK: - onStateChange Callback

    func testOnStateChangeCalledWhenSpeaking() {
        let synth = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: synth)
        var receivedStates: [SpeakerState] = []
        speaker.onStateChange = { receivedStates.append($0) }

        speaker.speakImmediate("Hello")

        XCTAssertEqual(receivedStates, [.speaking])
    }

    func testOnStateChangeCalledWhenFinished() {
        let synth = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: synth)
        var receivedStates: [SpeakerState] = []

        speaker.speakImmediate("Hello")
        speaker.onStateChange = { receivedStates.append($0) }

        synth.isSpeakingValue = false
        synth.simulateDidFinish()

        XCTAssertEqual(receivedStates, [.idle])
    }

    func testOnStateChangeNotCalledForSameState() {
        let synth = MockSpeechSynthesizer()
        let speaker = ResponseSpeaker(synthesizer: synth)
        var callCount = 0
        speaker.onStateChange = { _ in callCount += 1 }

        // Already idle, interrupt should not trigger callback
        speaker.interrupt()

        XCTAssertEqual(callCount, 0)
    }
