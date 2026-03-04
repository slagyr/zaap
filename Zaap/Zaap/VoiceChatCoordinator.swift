import Foundation
import Combine

// MARK: - Protocols for Dependency Injection

/// Abstracts VoiceEngine for testability.
protocol VoiceEngineProtocol: AnyObject {
    var isListening: Bool { get }
    var currentTranscript: String { get }
    var silenceThreshold: TimeInterval { get }
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
    func listSessions(limit: Int?, activeMinutes: Int?, includeDerivedTitles: Bool, includeLastMessage: Bool) async throws -> [GatewaySession]
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
    private let operatorGateway: GatewayConnecting?
    private let speaker: ResponseSpeaking
    private var sessionKey: String = ""
    @Published private(set) var isSessionActive = false
    @Published private(set) var isConversationModeOn = false
    private let thinkingSoundPlayer: ThinkingSoundPlaying?
    weak var sessionPicker: SessionPickerViewModel? {
        didSet { operatorDelegate?.sessionPicker = sessionPicker }
    }
    let needsRepairingPublisher = PassthroughSubject<Void, Never>()
    var logHandler: (String) -> Void = { AppLog.shared.log($0) }
    var micRestartDelay: TimeInterval = 0.5
    private var micRestartTask: Task<Void, Never>?
    private var recentSpokenTexts: [String] = []
    private let maxSpokenTextHistory = 10
    private var operatorDelegate: OperatorGatewayDelegate?

    init(viewModel: VoiceChatViewModel,
         voiceEngine: VoiceEngineProtocol,
         gateway: GatewayConnecting,
         speaker: ResponseSpeaking,
         operatorGateway: GatewayConnecting? = nil,
         thinkingSoundPlayer: ThinkingSoundPlaying? = nil) {
        self.viewModel = viewModel
        self.voiceEngine = voiceEngine
        self.gateway = gateway
        self.operatorGateway = operatorGateway
        self.speaker = speaker
        self.thinkingSoundPlayer = thinkingSoundPlayer

        gateway.delegate = self

        if let opGw = operatorGateway {
            let opDelegate = OperatorGatewayDelegate()
            opDelegate.logHandler = logHandler
            self.operatorDelegate = opDelegate
            opGw.delegate = opDelegate
        }

        speaker.onStateChange = { [weak self] newState in
            guard let self = self else { return }
            self.logHandler("🔊 [SPEAKER] state → \(newState) sessionActive=\(self.isSessionActive) conversationMode=\(self.isConversationModeOn)")
            guard self.isSessionActive else { return }
            if newState == .speaking {
                // Stop thinking sound — response is arriving
                self.thinkingSoundPlayer?.stopPlaying()
                // Stop mic during TTS to prevent echo pickup (hardware AEC insufficient on device)
                self.logHandler("🔊 [SPEAKER] stopping mic for TTS playback")
                self.voiceEngine.stopListening()
            } else if newState == .idle, self.isConversationModeOn {
                self.logHandler("🔊 [SPEAKER] TTS finished, scheduling mic restart")
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

    /// Connect both gateways eagerly (e.g. on view appear) so sessions load
    /// without starting a voice session.
    func connectGateway(url: URL) {
        if gateway.state == .disconnected {
            gateway.connect(to: url)
        }
        if let opGw = operatorGateway, opGw.state == .disconnected {
            opGw.connect(to: url)
        }
    }

    // MARK: - Session Management

    func updateSessionKey(_ key: String) {
        let wasActive = isSessionActive
        let wasConversationMode = isConversationModeOn

        // If session is active, flush any in-flight transcript to the OLD session
        // before switching keys, so mid-sentence speech isn't silently discarded. (zaap-cxe)
        if wasActive {
            flushPendingTranscript()
        }

        sessionKey = key

        // If session is active, cleanly reset voice state for the new session (zaap-wiu)
        if wasActive {
            voiceEngine.stopListening()
            speaker.interrupt()
            micRestartTask?.cancel()
            micRestartTask = nil

            // Clear in-flight partial/response text and reset VM to idle
            viewModel.loadPreviewMessages(viewModel.conversationLog)
            if viewModel.state != .idle {
                viewModel.tapMic() // → idle
            }

            // Show brief session-switch notification (zaap-cxe)
            viewModel.showSessionSwitchNotice = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                viewModel.showSessionSwitchNotice = false
            }

            // Restart mic after delay if conversation mode was on
            if wasConversationMode {
                scheduleMicRestart()
            }
        }
    }

    /// Send any in-flight partial transcript to the current (old) session before switching.
    private func flushPendingTranscript() {
        let pending = voiceEngine.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending.count >= 3 else { return }
        logHandler("🎙️ [COORD] flushing pending transcript to session \(sessionKey): \"\(pending.prefix(50))\"")
        handleUtteranceComplete(pending)
    }

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
            speaker.interrupt()
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
        thinkingSoundPlayer?.stopPlaying()
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
        logHandler("🎙️ [COORD] scheduleMicRestart: delay=\(micRestartDelay)s")
        micRestartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(micRestartDelay * 1_000_000_000))
            guard !Task.isCancelled else {
                logHandler("🎙️ [COORD] micRestart: cancelled")
                return
            }
            guard isSessionActive, isConversationModeOn else {
                logHandler("🎙️ [COORD] micRestart: skipped (sessionActive=\(isSessionActive) conversationMode=\(isConversationModeOn))")
                return
            }
            logHandler("🎙️ [COORD] micRestart: restarting voice engine, vmState=\(viewModel.state)")
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
        thinkingSoundPlayer?.startPlaying()

        let key = sessionKey
        Task {
            try? await gateway.sendVoiceTranscript(text, sessionKey: key)
        }
    }

    // MARK: - GatewayConnectionDelegate

    nonisolated func gatewayDidConnect() {
        Task { @MainActor in
            // Load sessions via operator gateway if no separate operator connection exists
            if operatorGateway == nil {
                await sessionPicker?.loadSessions()
            }
            guard isSessionActive, isConversationModeOn else { return }
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
        // Filter by session key — only process events for the active session.
        // Drop silently to avoid flooding the log buffer with high-frequency mismatches.
        let eventSessionKey = payload["sessionKey"] as? String
        if eventSessionKey != nil, eventSessionKey != sessionKey {
            return
        }

        logHandler("📥 [VOICE] event=\(event) sessionActive=\(isSessionActive)")

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
        // Chat events must have a matching session key (already filtered for mismatches above,
        // but we also need to reject events with no session key at all)
        guard let eventKey = payload["sessionKey"] as? String, eventKey == sessionKey else { return }
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
            thinkingSoundPlayer?.stopPlaying()
            logHandler("📥 [VOICE] chat final: text=\(text?.prefix(50) ?? "nil") sessionActive=\(isSessionActive) conversationMode=\(isConversationModeOn)")
            // Set authoritative final text before completing (zaap-9nl)
            if let t = text, !t.isEmpty {
                viewModel.setResponseText(t)
            }
            if isSessionActive, isConversationModeOn, let t = text, !t.isEmpty {
                trackSpokenText(t)
                speaker.bufferToken(t)
            }
            if isSessionActive, isConversationModeOn {
                speaker.flush()
            }
            viewModel.handleResponseComplete()
        case "error":
            logHandler("❌ [VOICE] chat error event received")
            thinkingSoundPlayer?.stopPlaying()
            viewModel.handleResponseComplete()
        default:
            logHandler("⚠️ [VOICE] unhandled chat state=\(state)")
        }
    }
}

// MARK: - Operator Gateway Delegate

/// Lightweight delegate for the operator gateway connection.
/// Loads sessions when connected. Does NOT forward challengeFailed to needsRepairingPublisher
/// because operator auth failures are expected during first-time role-upgrade pairing and
/// should not wipe the node's valid pairing state.
final class OperatorGatewayDelegate: GatewayConnectionDelegate {
    weak var sessionPicker: SessionPickerViewModel?
    var logHandler: (String) -> Void = { AppLog.shared.log($0) }

    nonisolated func gatewayDidConnect() {
        Task { @MainActor in
            await sessionPicker?.loadSessions()
        }
    }

    nonisolated func gatewayDidDisconnect() {}

    nonisolated func gatewayDidReceiveEvent(_ event: String, payload: [String: Any]) {}

    nonisolated func gatewayDidFailWithError(_ error: GatewayConnectionError) {
        switch error {
        case .challengeFailed(let msg):
            logHandler("⚠️ [OPERATOR] auth failed (role-upgrade needed?): \(msg)")
        case .requestFailed(let msg):
            logHandler("⚠️ [OPERATOR] request failed: \(msg)")
        default:
            break
        }
    }
}
