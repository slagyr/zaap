import SwiftUI
import Speech

struct VoiceChatView: View {
    @StateObject private var viewModel: VoiceChatViewModel
    @StateObject private var coordinator: VoiceChatCoordinator
    @StateObject private var sessionPicker: SessionPickerViewModel
    @State private var isPaired = NodePairingManager(keychain: RealKeychain()).isPaired

    init() {
        let vm = VoiceChatViewModel()
        let engine = VoiceEngine(
            speechRecognizer: RealSpeechRecognizer(),
            audioEngine: RealAudioEngineProvider(),
            audioSession: RealAudioSessionConfigurator(),
            timerFactory: RealTimerFactory()
        )
        let gateway = GatewayConnection(
            pairingManager: NodePairingManager(keychain: RealKeychain()),
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
        _sessionPicker = StateObject(wrappedValue: SessionPickerViewModel(sessionLister: gateway))
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
        .navigationTitle("Voice")
        .onAppear {
            // Check if device is already paired with gateway
            let mgr = NodePairingManager(keychain: RealKeychain())
            isPaired = mgr.isPaired
            if isPaired {
                Task { await sessionPicker.loadSessions() }
            }
            // Request microphone + speech recognition authorization
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
        .onReceive(coordinator.needsRepairingPublisher) {
            // Auth failed — token is stale or invalid, force re-pairing
            NodePairingManager(keychain: RealKeychain()).clearPairing()
            isPaired = false
        }
    }

    private var micUI: some View {
        VStack(spacing: 0) {
            // Conversation log
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
                    }
                    .padding()
                }
                .onChange(of: viewModel.conversationLog.count) { _, _ in
                    if let last = viewModel.conversationLog.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            SessionPickerView(viewModel: sessionPicker)
                .padding(.horizontal)

            Divider()

            // Status & mic button
            VStack(spacing: 12) {
                statusView
                micButton
            }
            .padding()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.state {
        case .idle:
            Text("Tap to start")
                .foregroundColor(.secondary)
        case .listening:
            HStack(spacing: 8) {
                WaveformIndicator()
                Text("Listening...")
                    .foregroundColor(.blue)
            }
        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Thinking...")
                    .foregroundColor(.orange)
            }
        case .speaking:
            HStack(spacing: 8) {
                SpeakerIndicator()
                Text("Speaking...")
                    .foregroundColor(.green)
            }
        }
    }

    private var micButton: some View {
        Button(action: {
            switch viewModel.state {
            case .idle:
                if let url = SettingsManager.shared.voiceWebSocketURL {
                    coordinator.startSession(gatewayURL: url, sessionKey: sessionPicker.activeSessionKey)
                } else {
                    viewModel.updatePartialTranscript("⚠️ Configure gateway URL in Settings first")
                }
            default:
                coordinator.stopSession()
            }
        }) {
            Image(systemName: micIconName)
                .font(.system(size: 32))
                .frame(width: 72, height: 72)
                .foregroundColor(.white)
                .background(micButtonColor)
                .clipShape(Circle())
        }
        .accessibilityLabel(micAccessibilityLabel)
    }

    private var micIconName: String {
        switch viewModel.state {
        case .idle: return "mic"
        case .listening: return "mic.fill"
        case .processing: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private var micButtonColor: Color {
        switch viewModel.state {
        case .idle: return .blue
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .green
        }
    }

    private var micAccessibilityLabel: String {
        switch viewModel.state {
        case .idle: return "Start listening"
        case .listening: return "Stop listening"
        case .processing: return "Processing"
        case .speaking: return "Stop speaking"
        }
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
