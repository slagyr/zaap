import Foundation

// MARK: - Voice Chat State

enum VoiceChatState: Equatable {
    case idle
    case listening
    case processing
    case speaking
}

// MARK: - Conversation Entry

enum ConversationRole: Equatable {
    case user
    case agent
}

struct ConversationEntry: Equatable, Identifiable {
    let id = UUID()
    let role: ConversationRole
    let text: String

    static func == (lhs: ConversationEntry, rhs: ConversationEntry) -> Bool {
        lhs.role == rhs.role && lhs.text == rhs.text
    }
}

// MARK: - VoiceChatViewModel

@MainActor
final class VoiceChatViewModel: ObservableObject {
    @Published private(set) var state: VoiceChatState = .idle
    @Published private(set) var conversationLog: [ConversationEntry] = []
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var responseText: String = ""

    func tapMic() {
        switch state {
        case .idle:
            state = .listening
        case .listening, .processing, .speaking:
            state = .idle
            partialTranscript = ""
            responseText = ""
        }
    }

    func updatePartialTranscript(_ text: String) {
        partialTranscript = text
    }

    func handleUtteranceComplete(_ text: String) {
        partialTranscript = ""
        conversationLog.append(ConversationEntry(role: .user, text: text))
        state = .processing
    }

    func handleResponseToken(_ token: String) {
        responseText += token
        if state == .processing {
            state = .speaking
        }
    }

    /// Set the full response text (for streaming sources that send cumulative text, not incremental tokens)
    func setResponseText(_ text: String) {
        responseText = text
        if state == .processing {
            state = .speaking
        }
    }

    func handleResponseComplete() {
        if !responseText.isEmpty {
            conversationLog.append(ConversationEntry(role: .agent, text: responseText))
        }
        responseText = ""
        state = .listening
    }
}
