import AVFoundation

/// Protocol abstracting AVSpeechSynthesizer for testability.
protocol SpeechSynthesizing: AnyObject {
    var delegate: (any AVSpeechSynthesizerDelegate)? { get set }
    var isSpeaking: Bool { get }
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

/// State of the ResponseSpeaker.
enum SpeakerState: Equatable {
    case idle
    case speaking
}

/// Speaks streamed text from the gateway using AVSpeechSynthesizer.
///
/// Buffers incoming tokens until a sentence boundary is detected, then speaks
/// each sentence. Supports interrupt() to stop mid-speech when the user starts
/// talking. Publishes state (idle/speaking) for UI.
final class ResponseSpeaker: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer: SpeechSynthesizing
    private var buffer: String = ""

    /// Current speaker state, observable by UI.
    private(set) var state: SpeakerState = .idle

    init(synthesizer: SpeechSynthesizing) {
        self.synthesizer = synthesizer
        super.init()
        self.synthesizer.delegate = self
    }

    // MARK: - Sentence Extraction

    /// Result of extracting complete sentences from a text buffer.
    struct ExtractionResult: Equatable {
        let sentences: [String]
        let remainder: String
    }

    /// Extracts complete sentences from a buffer, returning them and any remainder.
    ///
    /// Sentence boundaries are `.`, `!`, and `?`.
    static func extractSentences(from text: String) -> ExtractionResult {
        guard !text.isEmpty else {
            return ExtractionResult(sentences: [], remainder: "")
        }

        var sentences: [String] = []
        var currentStart = text.startIndex

        for i in text.indices {
            let char = text[i]
            if char == "." || char == "!" || char == "?" {
                let endIndex = text.index(after: i)
                let sentence = String(text[currentStart..<endIndex])
                sentences.append(sentence)
                currentStart = endIndex
            }
        }

        let remainder = String(text[currentStart...])
        return ExtractionResult(sentences: sentences, remainder: remainder)
    }

    // MARK: - Speaking

    /// Speak a complete text immediately.
    func speakImmediate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
        state = .speaking
    }

    /// Buffer a streaming token. When a sentence boundary is detected, the
    /// complete sentence is spoken immediately.
    func bufferToken(_ token: String) {
        buffer.append(token)

        let result = Self.extractSentences(from: buffer)
        buffer = result.remainder

        for sentence in result.sentences {
            speakImmediate(sentence)
        }
    }

    /// Flush any remaining buffered text as speech.
    func flush() {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !trimmed.isEmpty else { return }
        speakImmediate(trimmed)
    }

    /// Interrupt current speech and clear buffer. Call when the user starts
    /// speaking to allow them to take over.
    func interrupt() {
        buffer = ""
        guard state == .speaking else { return }
        _ = synthesizer.stopSpeaking(at: .immediate)
        state = .idle
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        handleDidFinish()
    }

    /// Called when an utterance finishes (also used by mock).
    func handleDidFinish() {
        if !synthesizer.isSpeaking {
            state = .idle
        }
    }
}
