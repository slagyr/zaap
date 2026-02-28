import SwiftUI
import Speech

struct VoiceChatView: View {
    @StateObject private var viewModel: VoiceChatViewModel
    @State private var showCopied = false
    @StateObject private var coordinator: VoiceChatCoordinator
    @StateObject private var sessionPicker: SessionPickerViewModel
    @State private var isPaired = false

    init() {
        let vm = VoiceChatViewModel()
        let engine = VoiceEngine(
            speechRecognizer: RealSpeechRecognizer(),
            audioEngine: RealAudioEngineProvider(),
            audioSession: RealAudioSessionConfigurator(),
            timerFactory: RealTimerFactory()
        )
        let gateway = GatewayConnection(
            pairingManager: NodePairingManager(),
            webSocketFactory: URLSessionWebSocketFactory(),
            networkMonitor: NWNetworkMonitor()
        )
        let speaker = ResponseSpeaker(synthesizer: AVSpeechSynthesizer())
        let coord = VoiceChatCoordinator(
            viewModel: vm,
            voiceEngine: engine,
            gateway: gateway,
            speaker: speaker
        )
        _viewModel = StateObject(wrappedValue: vm)
        _coordinator = StateObject(wrappedValue: coord)
        let picker = SessionPickerViewModel(sessionLister: gateway)
        coord.sessionPicker = picker
        _sessionPicker = StateObject(wrappedValue: picker)
    }

    var body: some View {
        Group {
            if isPaired {
                micUI
            } else {
                VoicePairingView(onPaired: {
                    isPaired = true
                })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Check if device is already paired with gateway
            let mgr = NodePairingManager()
            isPaired = mgr.isPaired
            // Sessions load automatically when gateway connects (see VoiceChatCoordinator.gatewayDidConnect)
            // Request microphone + speech recognition authorization
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
        .onReceive(coordinator.needsRepairingPublisher) {
            // Auth failed — token is stale or invalid, force re-pairing
            NodePairingManager().clearPairing()
            isPaired = false
        }
    }

    private var micUI: some View {
        VStack(spacing: 0) {
            // Conversation log — fills all remaining vertical space
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.conversationLog) { entry in
                            ConversationBubble(entry: entry)
                                .id(entry.id)
                        }

                        // Partial transcript while listening
                        if !viewModel.partialTranscript.isEmpty {
                            Text(viewModel.partialTranscript)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.horizontal)
                        }

                        // Response text while speaking
                        if !viewModel.responseText.isEmpty {
                            ConversationBubble(entry: ConversationEntry(role: .agent, text: viewModel.responseText))
                        }

                        // Invisible anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                    }
                    .padding()
                }
                .overlay {
                    // Hint floats in transcript area, doesn't add toolbar height
                    if viewModel.conversationLog.isEmpty && viewModel.state == .idle {
                        Text("Tap the mic to start")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                .onChange(of: viewModel.conversationLog.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.partialTranscript) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.responseText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Compact single-row toolbar: [session picker] --- [status] --- [mic 44pt]
            HStack(spacing: 12) {
                compactSessionPicker
                Spacer()
                copyButton
                statusDot
                micButton
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Compact Session Picker (Menu style)

    private var compactSessionPicker: some View {
        Menu {
            Picker("Session", selection: $sessionPicker.selectedSessionKey) {
                ForEach(sessionPicker.sessions) { session in
                    Text(session.title)
                        .tag(session.key)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 14))
                Text(sessionPicker.selectedSessionTitle)
                    .lineLimit(1)
                    .font(.subheadline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(.primary)
        }
    }

    // MARK: - Status Dot (compact indicator)

    @ViewBuilder
    private var statusDot: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .listening:
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .speaking:
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Mic Button (44pt compact)

    private var micButton: some View {
        Button(action: {
            if coordinator.isSessionActive {
                coordinator.toggleConversationMode()
            } else {
                if let url = SettingsManager.shared.voiceWebSocketURL {
                    coordinator.startSession(gatewayURL: url, sessionKey: sessionPicker.activeSessionKey)
                } else {
                    viewModel.updatePartialTranscript("⚠️ Configure gateway URL in Settings first")
                }
            }
        }) {
            Image(systemName: micIconName)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .foregroundColor(.white)
                .background(micButtonColor)
                .clipShape(Circle())
        }
        .accessibilityLabel(micAccessibilityLabel)
        .disabled(!sessionPicker.isSessionSelected)
    }

    private var micIconName: String {
        coordinator.isConversationModeOn ? "mic.fill" : "mic"
    }

    private var copyButton: some View {
        Button(action: copyTranscript) {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Copy transcript")
    }

    private func copyTranscript() {
        let entries = viewModel.conversationLog.suffix(10)
        let text = entries.map { entry in
            let role = entry.role == .user ? "You" : "Zane"
            return "[\(role)]: \(entry.text)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
        withAnimation { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showCopied = false }
        }
    }

    private var micButtonColor: Color {
        coordinator.isConversationModeOn ? .red : .blue
    }

    private var micAccessibilityLabel: String {
        coordinator.isConversationModeOn ? "Turn off conversation mode" : "Turn on conversation mode"
    }
}

// MARK: - Conversation Bubble

struct ConversationBubble: View {
    let entry: ConversationEntry

    var body: some View {
        HStack {
            if entry.role == .user { Spacer() }

            Text(entry.text)
                .padding(12)
                .background(entry.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .cornerRadius(16)

            if entry.role == .agent { Spacer() }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Animated Indicators

struct WaveformIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 4, height: animating ? 16 : 8)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

struct SpeakerIndicator: View {
    @State private var animating = false

    var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .foregroundColor(.green)
            .scaleEffect(animating ? 1.15 : 1.0)
            .animation(
                .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true),
                value: animating
            )
            .onAppear { animating = true }
    }
}
