import Foundation
import Combine

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
    func listSessions(limit: Int, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession]
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
    let needsRepairingPublisher = PassthroughSubject<Void, Never>()

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

    func startSession(gatewayURL: URL, sessionKey: String? = nil) {
        self.sessionKey = sessionKey ?? UUID().uuidString
        isActive = true
        if gateway.state == .connected {
            // Already connected — go straight to listening
            viewModel.tapMic() // idle → listening
            voiceEngine.startListening()
        } else {
            // Connect first; gatewayDidConnect will start listening when ready
            gateway.connect(to: gatewayURL)
        }
    }

    func stopSession() {
        // Flush any partial transcript before stopping, so in-flight speech isn't lost
        let pending = voiceEngine.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPending = pending.count >= 3
        if hasPending {
            handleUtteranceComplete(pending) // sends transcript; sets state → .processing
        }

        voiceEngine.stopListening()
        speaker.interrupt()
        isActive = false

        // Don't disconnect — keep gateway connected so the response can still arrive
        // and next tap reuses the connection without handshake delay.

        // If we sent a transcript, leave the VM in .processing so the response bubble can appear.
        // handleChatEvent(final) will reset to idle when the response arrives.
        // If nothing was sent, reset to idle immediately.
        if !hasPending, viewModel.state != .idle {
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
            guard isActive else { return }
            // Gateway is ready — transition UI to listening and start capturing voice
            viewModel.tapMic() // idle → listening
            voiceEngine.startListening()
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
            // Auth failure means stale/invalid token — signal the view to re-pair
            if case .challengeFailed(_) = error {
                needsRepairingPublisher.send()
            }
        }
    }

    // MARK: - Gateway → ResponseSpeaker

    private func handleGatewayEvent(_ event: String, payload: [String: Any]) {
        // Always process incoming responses (agent may reply after user taps stop)

        // Handle gateway chat streaming events (delta/final from agent run)
        if event == "chat" {
            handleChatEvent(payload)
            return
        }

        // Legacy token/done events (kept for backward compat)
        let type = payload["type"] as? String ?? event
        switch type {
        case "token":
            if let text = payload["text"] as? String {
                viewModel.handleResponseToken(text)
                if isActive {
                    speaker.bufferToken(text)
                }
            }
        case "done":
            if isActive {
                speaker.flush()
            }
            viewModel.handleResponseComplete()
            voiceEngine.startListening()
        default:
            break
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String else { return }

        // Extract text from message.content[0].text
        let text: String? = {
            guard let message = payload["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]],
                  let first = content.first,
                  let t = first["text"] as? String else { return nil }
            return t
        }()

        switch state {
        case "delta":
            // Delta carries the full accumulated text so far — SET (don't append)
            if let t = text, !t.isEmpty {
                viewModel.setResponseText(t)
            }
        case "final":
            // Final carries the complete response — speak it only if session is still active
            if isActive, let t = text, !t.isEmpty {
                speaker.bufferToken(t)
            }
            if isActive {
                speaker.flush()
            }
            viewModel.handleResponseComplete() // → .listening state
            if isActive {
                voiceEngine.startListening()
            } else {
                viewModel.tapMic() // listening → idle (session was stopped by user)
            }
        case "error":
            viewModel.handleResponseComplete()
            if isActive {
                voiceEngine.startListening()
            } else {
                viewModel.tapMic()
            }
        default:
            break
        }
    }
}
