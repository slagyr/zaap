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
    var onStateChange: ((SpeakerState) -> Void)? { get set }
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
/// In conversation mode, mic stays hot across the listen→process→speak cycle (trusts AEC).
@MainActor
final class VoiceChatCoordinator: ObservableObject, GatewayConnectionDelegate {

    private let viewModel: VoiceChatViewModel
    private let voiceEngine: VoiceEngineProtocol
    private let gateway: GatewayConnecting
    private let speaker: ResponseSpeaking
    private var sessionKey: String = ""
    @Published private(set) var isSessionActive = false
    @Published private(set) var isConversationModeOn = false
    weak var sessionPicker: SessionPickerViewModel?
    let needsRepairingPublisher = PassthroughSubject<Void, Never>()
    var logHandler: (String) -> Void = { print($0) }
    var micRestartDelay: TimeInterval = 0.5
    private var micRestartTask: Task<Void, Never>?
    private var recentSpokenTexts: [String] = []
    private let maxSpokenTextHistory = 10

    init(viewModel: VoiceChatViewModel,
         voiceEngine: VoiceEngineProtocol,
         gateway: GatewayConnecting,
         speaker: ResponseSpeaking) {
        self.viewModel = viewModel
        self.voiceEngine = voiceEngine
        self.gateway = gateway
        self.speaker = speaker

        gateway.delegate = self

        speaker.onStateChange = { [weak self] newState in
            guard let self = self, self.isSessionActive else { return }
            if newState == .speaking {
                // Stop mic during TTS to prevent echo pickup (hardware AEC insufficient on device)
                self.voiceEngine.stopListening()
            } else if newState == .idle, self.isConversationModeOn {
                self.scheduleMicRestart()
            }
        }

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

    // MARK: - Gateway Connection

    /// Connect the gateway eagerly (e.g. on view appear) so sessions load
    /// without starting a voice session.
    func connectGateway(url: URL) {
        guard gateway.state == .disconnected else { return }
        gateway.connect(to: url)
    }

    // MARK: - Session Management

    func startSession(gatewayURL: URL, sessionKey: String? = nil) {
        self.sessionKey = sessionKey ?? UUID().uuidString
        isSessionActive = true
        isConversationModeOn = true
        if gateway.state == .connected {
            // Already connected — go straight to listening
            viewModel.tapMic() // idle → listening
            voiceEngine.startListening()
        } else {
            // Connect first; gatewayDidConnect will start listening when ready
            gateway.connect(to: gatewayURL)
        }
    }

    func toggleConversationMode() {
        guard isSessionActive else { return }
        if isConversationModeOn {
            isConversationModeOn = false
            micRestartTask?.cancel()
            micRestartTask = nil
            voiceEngine.stopListening()
            if viewModel.state == .listening {
                viewModel.tapMic() // listening → idle
            }
        } else {
            isConversationModeOn = true
            voiceEngine.startListening()
            if viewModel.state == .idle {
                viewModel.tapMic() // idle → listening
            }
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
        micRestartTask?.cancel()
        micRestartTask = nil
        isSessionActive = false
        isConversationModeOn = false

        // Don't disconnect — keep gateway connected so the response can still arrive
        // and next tap reuses the connection without handshake delay.

        // If we sent a transcript, leave the VM in .processing so the response bubble can appear.
        // handleChatEvent(final) will reset to idle when the response arrives.
        // If nothing was sent, reset to idle immediately.
        if !hasPending, viewModel.state != .idle {
            viewModel.tapMic()
        }
    }

    // MARK: - Mic Restart Delay

    private func scheduleMicRestart() {
        micRestartTask?.cancel()
        micRestartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(micRestartDelay * 1_000_000_000))
            guard !Task.isCancelled, isSessionActive, isConversationModeOn else { return }
            voiceEngine.startListening()
            if viewModel.state == .idle {
                viewModel.tapMic() // idle → listening
            }
        }
    }

    // MARK: - Echo Suppression

    /// Track text that was sent to TTS so we can filter STT echo.
    func trackSpokenText(_ text: String) {
        let normalized = Self.normalizeForEchoComparison(text)
        guard !normalized.isEmpty else { return }
        recentSpokenTexts.append(normalized)
        if recentSpokenTexts.count > maxSpokenTextHistory {
            recentSpokenTexts.removeFirst()
        }
    }

    /// Check if an STT transcript is likely echo of recently spoken TTS text.
    private func isEcho(_ transcript: String) -> Bool {
        let normalized = Self.normalizeForEchoComparison(transcript)
        guard !normalized.isEmpty else { return false }
        return recentSpokenTexts.contains { spoken in
            spoken.contains(normalized) || normalized.contains(spoken)
        }
    }

    /// Normalize text for echo comparison: lowercase, strip punctuation and extra whitespace.
    static func normalizeForEchoComparison(_ text: String) -> String {
        let lowered = text.lowercased()
        let stripped = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        let result = String(String.UnicodeScalarView(stripped))
        return result.split(separator: " ").joined(separator: " ")
    }

    // MARK: - Voice Engine → Gateway

    private func handleUtteranceComplete(_ text: String) {
        guard isSessionActive else { return }

        // Filter echo: if STT transcript matches recently spoken TTS text, discard it
        if isEcho(text) {
            logHandler("🔇 [VOICE] filtered echo: \"\(text.prefix(50))\"")
            return
        }

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
            // Load sessions whenever gateway connects (not just during active voice session)
            await sessionPicker?.loadSessions()
            guard isSessionActive else { return }
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
            switch error {
            case .challengeFailed:
                // Auth failure means stale/invalid token — signal the view to re-pair
                needsRepairingPublisher.send()
            case .requestFailed(let msg):
                logHandler("⚠️ [VOICE] request failed: \(msg)")
            default:
                break
            }
        }
    }

    // MARK: - Gateway → ResponseSpeaker

    private func handleGatewayEvent(_ event: String, payload: [String: Any]) {
        logHandler("📥 [VOICE] event=\(event) sessionActive=\(isSessionActive) keys=\(Array(payload.keys))")

        // Filter by session key — only process events for the active session
        if let eventSessionKey = payload["sessionKey"] as? String,
           eventSessionKey != sessionKey {
            logHandler("🚫 [VOICE] dropping event=\(event): session key mismatch (event=\(eventSessionKey) active=\(sessionKey))")
            return
        }

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
                if isSessionActive {
                    trackSpokenText(text)
                    speaker.bufferToken(text)
                }
            }
        case "done":
            if isSessionActive {
                speaker.flush()
            }
            viewModel.handleResponseComplete()
        default:
            logHandler("⚠️ [VOICE] unhandled legacy event type=\(type)")
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        // Require matching session key — ignore events from other sessions
        guard let eventSessionKey = payload["sessionKey"] as? String,
              eventSessionKey == sessionKey else {
            let eventKey = payload["sessionKey"] as? String ?? "<missing>"
            logHandler("🚫 [VOICE] dropping chat event: session key mismatch (event=\(eventKey) active=\(sessionKey))")
            return
        }
        guard let state = payload["state"] as? String else {
            logHandler("⚠️ [VOICE] chat event missing 'state' field")
            return
        }

        // Extract text from message.content[0].text
        let text: String? = {
            guard let message = payload["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]],
                  let first = content.first,
                  let t = first["text"] as? String else { return nil }
            return t
        }()

        if text == nil {
            logHandler("⚠️ [VOICE] chat state=\(state): text extraction returned nil from payload")
        }

        switch state {
        case "delta":
            if let t = text, !t.isEmpty {
                viewModel.setResponseText(t)
            }
        case "final":
            logHandler("📥 [VOICE] chat final: text=\(text?.prefix(50) ?? "nil") sessionActive=\(isSessionActive)")
            // Set authoritative final text before completing (zaap-9nl)
            if let t = text, !t.isEmpty {
                viewModel.setResponseText(t)
            }
            if isSessionActive, let t = text, !t.isEmpty {
                trackSpokenText(t)
                speaker.bufferToken(t)
            }
            if isSessionActive {
                speaker.flush()
            }
            viewModel.handleResponseComplete()
        case "error":
            logHandler("❌ [VOICE] chat error event received")
            viewModel.handleResponseComplete()
        default:
            logHandler("⚠️ [VOICE] unhandled chat state=\(state)")
        }
    }
}
