import Foundation

// MARK: - Protocols for Dependency Injection

/// Abstracts VoiceEngine for testability.
protocol VoiceEngineProtocol: AnyObject {
    var isListening: Bool { get }
    var currentTranscript: String { get }
    var onUtteranceComplete: ((String) -> Void)? { get set }
    var onPartialTranscript: ((String) -> Void)? { get set }
    var onError: ((VoiceEngineError) -> Void)? { get set }
    func startListening()
    func stopListening()
}

/// Abstracts GatewayConnection for testability.
protocol GatewayConnecting: AnyObject {
    var state: ConnectionState { get }
    var delegate: GatewayConnectionDelegate? { get set }
    func connect(to url: URL)
    func disconnect()
    func sendVoiceTranscript(_ text: String, sessionKey: String) async throws
}

extension GatewayConnection: GatewayConnecting {}

/// Abstracts ResponseSpeaker for testability.
protocol ResponseSpeaking: AnyObject {
    var state: SpeakerState { get }
    func speakImmediate(_ text: String)
    func bufferToken(_ token: String)
    func flush()
    func interrupt()
}

extension ResponseSpeaker: ResponseSpeaking {}

// MARK: - VoiceChatCoordinator

/// Wires the voice pipeline together:
/// VoiceEngine transcript → GatewayConnection voice.transcript event
/// → receive chat.event stream → ResponseSpeaker speaks response.
/// Handles interrupts when user speaks while TTS is playing.
@MainActor
final class VoiceChatCoordinator: ObservableObject, GatewayConnectionDelegate {

    private let viewModel: VoiceChatViewModel
    private let voiceEngine: VoiceEngineProtocol
    private let gateway: GatewayConnecting
    private let speaker: ResponseSpeaking
    private var sessionKey: String = ""
    private var isActive = false

    init(viewModel: VoiceChatViewModel,
         voiceEngine: VoiceEngineProtocol,
         gateway: GatewayConnecting,
         speaker: ResponseSpeaking) {
        self.viewModel = viewModel
        self.voiceEngine = voiceEngine
        self.gateway = gateway
        self.speaker = speaker

        gateway.delegate = self

        voiceEngine.onPartialTranscript = { [weak self] text in
            self?.viewModel.updatePartialTranscript(text)
        }

        voiceEngine.onUtteranceComplete = { [weak self] text in
            self?.handleUtteranceComplete(text)
        }

        voiceEngine.onError = { [weak self] error in
            switch error {
            case .notAuthorized:
                self?.viewModel.updatePartialTranscript("⚠️ Microphone not authorized")
            case .recognizerUnavailable:
                self?.viewModel.updatePartialTranscript("⚠️ Speech recognizer unavailable")
            case .recognitionFailed(let msg):
                self?.viewModel.updatePartialTranscript("⚠️ \(msg)")
            case .audioSessionFailed(let msg):
                self?.viewModel.updatePartialTranscript("⚠️ Audio error: \(msg)")
            }
        }
    }

    // MARK: - Session Management

    func startSession(gatewayURL: URL) {
        sessionKey = UUID().uuidString
        isActive = true
        viewModel.tapMic() // idle → listening
        voiceEngine.startListening()
        gateway.connect(to: gatewayURL)
    }

    func stopSession() {
        isActive = false
        voiceEngine.stopListening()
        speaker.interrupt()
        gateway.disconnect()
        // Reset VM to idle
        if viewModel.state != .idle {
            viewModel.tapMic()
        }
    }

    // MARK: - Voice Engine → Gateway

    private func handleUtteranceComplete(_ text: String) {
        guard isActive else { return }

        // Interrupt speaker if currently speaking
        if speaker.state == .speaking {
            speaker.interrupt()
        }

        viewModel.handleUtteranceComplete(text)

        let key = sessionKey
        Task {
            try? await gateway.sendVoiceTranscript(text, sessionKey: key)
        }
    }

    // MARK: - GatewayConnectionDelegate

    nonisolated func gatewayDidConnect() {
        Task { @MainActor in
            // Connection established, ready for voice
        }
    }

    nonisolated func gatewayDidDisconnect() {
        Task { @MainActor in
            // Could trigger reconnection UI
        }
    }

    nonisolated func gatewayDidReceiveEvent(_ event: String, payload: [String: Any]) {
        Task { @MainActor in
            self.handleGatewayEvent(event, payload: payload)
        }
    }

    nonisolated func gatewayDidFailWithError(_ error: GatewayConnectionError) {
        Task { @MainActor in
            // Could surface error to UI
        }
    }

    // MARK: - Gateway → ResponseSpeaker

    private func handleGatewayEvent(_ event: String, payload: [String: Any]) {
        guard isActive else { return }

        let type = payload["type"] as? String ?? event

        switch type {
        case "token":
            if let text = payload["text"] as? String {
                viewModel.handleResponseToken(text)
                speaker.bufferToken(text)
            }
        case "done":
            speaker.flush()
            viewModel.handleResponseComplete()
            // Resume listening
            voiceEngine.startListening()
        default:
            break
        }
    }
}
