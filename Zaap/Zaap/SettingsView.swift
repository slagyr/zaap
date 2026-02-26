import SwiftUI
import AVFoundation

enum SendNowStatus: Equatable {
    case idle
    case sending
    case success
    case failure(String)
}

struct SettingsView: View {

    @Bindable var settings: SettingsManager
    var testService: WebhookTestService?
    @ObservedObject var requestLog: RequestLog = .shared
    var gatewayBrowser: GatewayBrowserViewModel?
    var pairingViewModel: PairingViewModel?

    @State private var isTokenVisible = false
    @State private var isGatewayTokenVisible = false
    @State private var isTesting = false
    @State private var testResult: WebhookTestService.TestResult?
    @State private var locationSendStatus: SendNowStatus = .idle
    @State private var sleepSendStatus: SendNowStatus = .idle
    @State private var workoutSendStatus: SendNowStatus = .idle
    @State private var heartRateSendStatus: SendNowStatus = .idle
    @State private var activitySendStatus: SendNowStatus = .idle

    // TTS voice picker
    @State private var availableVoices: [(id: String, name: String)] = []
    @State private var previewSynthesizer = AVSpeechSynthesizer()
    @State private var isPreviewPlaying = false

    #if targetEnvironment(simulator)
    @StateObject private var seeder = HealthDataSeeder()
    #endif

    var body: some View {
        Form {
            Section {
                Toggle("Use development config?", isOn: $settings.useDevConfig)

                #if targetEnvironment(simulator)
                Button {
                    seeder.seedAll()
                } label: {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text("Seed Health Data")
                    }
                }
                .disabled(seeder.status == .seeding)

                switch seeder.status {
                case .seeding:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Seeding…").foregroundStyle(.secondary).font(.subheadline)
                    }
                case .done(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failed(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                case .idle:
                    EmptyView()
                }
                #endif
            } header: {
                Text("Configuration")
            } footer: {
                Text(settings.useDevConfig
                     ? "Development: localhost:8788 (for testing)"
                     : "Production: REDACTED_HOSTNAME")
                    .font(.caption)
            }

            if let pairingVM = pairingViewModel {
                PairingSectionView(viewModel: pairingVM)
            }

            if let browser = gatewayBrowser, browser.hasDiscoveredGateways {
                Section {
                    ForEach(browser.discoveredGateways) { gateway in
                        Button {
                            browser.selectGateway(gateway)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(gateway.displayName)
                                        .foregroundStyle(.primary)
                                    Text(gateway.hostnameWithPort)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.webhookURL == gateway.hostnameWithPort {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Discovered Gateways")
                        Spacer()
                        if browser.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section {
                TextField("Hostname", text: $settings.webhookURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Group {
                        if isTokenVisible {
                            TextField("Hooks Bearer Token", text: $settings.authToken)
                        } else {
                            SecureField("Hooks Bearer Token", text: $settings.authToken)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Group {
                        if isGatewayTokenVisible {
                            TextField("Gateway Bearer Token", text: $settings.gatewayToken)
                        } else {
                            SecureField("Gateway Bearer Token", text: $settings.gatewayToken)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        isGatewayTokenVisible.toggle()
                    } label: {
                        Image(systemName: isGatewayTokenVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            } header: {
                Text("Server")
            } footer: {
                if settings.hostname.isEmpty {
                    Text("Enter your OpenClaw gateway hostname (e.g. myhost.ts.net)")
                } else {
                    Text("Webhooks: https://\(settings.hostname)/hooks/…\nVoice: \(settings.isLocalHostname ? "ws" : "wss")://\(settings.hostname)")
                }
            }

            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing…")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                .disabled(isTesting || !settings.isConfigured)

                if let testResult {
                    HStack {
                        Image(systemName: testResult.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testResult.success ? .green : .red)
                        Text(testResult.success ? "Connection successful" : (testResult.errorMessage ?? "Unknown error"))
                            .font(.subheadline)
                            .foregroundStyle(testResult.success ? .green : .red)
                    }
                }
            }

            Section {
                if availableVoices.isEmpty {
                    Text("No voices available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Response Voice", selection: $settings.ttsVoiceIdentifier) {
                        Text("System Default").tag("")
                        ForEach(availableVoices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: settings.ttsVoiceIdentifier) { _, _ in
                        // Auto-preview when a new voice is selected
                        playVoicePreview()
                    }

                    Button {
                        if isPreviewPlaying {
                            previewSynthesizer.stopSpeaking(at: .immediate)
                            isPreviewPlaying = false
                        } else {
                            playVoicePreview()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isPreviewPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .foregroundStyle(isPreviewPlaying ? .red : .blue)
                                .font(.title3)
                            Text(isPreviewPlaying ? "Stop Preview" : "Preview Voice")
                                .foregroundStyle(isPreviewPlaying ? .red : .blue)
                        }
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Tap Preview to hear the selected voice. Enhanced ✦ and Premium ⭐️ voices sound more natural and must be downloaded in iOS Settings → Accessibility → Spoken Content → Voices.")
            }

            Section {
                dataSourceRow(
                    label: "Location Tracking",
                    isOn: $settings.locationTrackingEnabled,
                    status: $locationSendStatus,
                    onToggle: { enabled in LocationDeliveryService.shared.setTracking(enabled: enabled) },
                    onSendNow: { try await LocationDeliveryService.shared.sendNow() }
                )

                dataSourceRow(
                    label: "Sleep Tracking",
                    isOn: $settings.sleepTrackingEnabled,
                    status: $sleepSendStatus,
                    onToggle: { enabled in SleepDeliveryService.shared.setTracking(enabled: enabled) },
                    onSendNow: { try await SleepDeliveryService.shared.sendNow() }
                )

                dataSourceRow(
                    label: "Workout Tracking",
                    isOn: $settings.workoutTrackingEnabled,
                    status: $workoutSendStatus,
                    onToggle: { enabled in WorkoutDeliveryService.shared.setTracking(enabled: enabled) },
                    onSendNow: { try await WorkoutDeliveryService.shared.sendNow() }
                )

                dataSourceRow(
                    label: "Heart Rate Tracking",
                    isOn: $settings.heartRateTrackingEnabled,
                    status: $heartRateSendStatus,
                    onToggle: { enabled in HeartRateDeliveryService.shared.setTracking(enabled: enabled) },
                    onSendNow: { try await HeartRateDeliveryService.shared.sendNow() }
                )

                dataSourceRow(
                    label: "Activity Tracking",
                    isOn: $settings.activityTrackingEnabled,
                    status: $activitySendStatus,
                    onToggle: { enabled in ActivityDeliveryService.shared.setTracking(enabled: enabled) },
                    onSendNow: { try await ActivityDeliveryService.shared.sendNow() }
                )
            } header: {
                Text("Data Sources")
            } footer: {
                if !settings.isConfigured && (settings.locationTrackingEnabled || settings.sleepTrackingEnabled || settings.workoutTrackingEnabled) {
                    Text("⚠️ Configure a valid webhook URL and token above to start sending data.")
                        .foregroundStyle(.orange)
                }
            }

            RequestLogView(log: requestLog)

        }
        .navigationTitle("Settings")
        .onAppear {
            gatewayBrowser?.startSearching()
            loadAvailableVoices()
        }
        .onDisappear { gatewayBrowser?.stopSearching() }
    }

    // MARK: - Data Source Row

    @ViewBuilder
    private func dataSourceRow(
        label: String,
        isOn: Binding<Bool>,
        status: Binding<SendNowStatus>,
        onToggle: @escaping (Bool) -> Void,
        onSendNow: @escaping () async throws -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(label, isOn: isOn)
                .onChange(of: isOn.wrappedValue) { _, enabled in
                    onToggle(enabled)
                }

            HStack(spacing: 8) {
                Button {
                    Task {
                        status.wrappedValue = .sending
                        do {
                            try await onSendNow()
                            status.wrappedValue = .success
                        } catch {
                            status.wrappedValue = .failure(error.localizedDescription)
                        }
                        try? await Task.sleep(for: .seconds(3))
                        if status.wrappedValue != .sending {
                            status.wrappedValue = .idle
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if status.wrappedValue == .sending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle")
                        }
                        Text("Send Now")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!settings.isConfigured || status.wrappedValue == .sending)

                switch status.wrappedValue {
                case .success:
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                default:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Voice Preview

    private func playVoicePreview() {
        previewSynthesizer.stopSpeaking(at: .immediate)

        let sampleText = "Hi, I'm your voice assistant. Just ask me anything."
        let utterance = AVSpeechUtterance(string: sampleText)

        let voiceId = settings.ttsVoiceIdentifier
        utterance.voice = voiceId.isEmpty
            ? AVSpeechSynthesisVoice(language: "en-US")
            : AVSpeechSynthesisVoice(identifier: voiceId) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        isPreviewPlaying = true
        // Use a delegate-free approach: monitor via notification or just reset after a delay.
        // AVSpeechSynthesizer needs a delegate object — use a simple one-shot wrapper.
        let monitor = SpeechFinishMonitor { [self] in
            isPreviewPlaying = false
        }
        previewSynthesizer.delegate = monitor
        // Keep monitor alive for the duration of the utterance
        objc_setAssociatedObject(previewSynthesizer, &Self.monitorKey, monitor, .OBJC_ASSOCIATION_RETAIN)

        previewSynthesizer.speak(utterance)
    }

    private static var monitorKey: UInt8 = 0

    // MARK: - Voice Loading

    private func loadAvailableVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let english = all.filter { $0.language.hasPrefix("en") }

        // Sort: Premium first, then Enhanced, then everything else; alphabetical within tier
        let sorted = english.sorted { a, b in
            let tierA = voiceTier(a)
            let tierB = voiceTier(b)
            if tierA != tierB { return tierA < tierB }
            return a.name < b.name
        }

        availableVoices = sorted.map { voice in
            let tier = voiceTierLabel(voice)
            let lang = voice.language == "en-US" ? "" : " (\(voice.language))"
            return (id: voice.identifier, name: "\(voice.name)\(lang)\(tier)")
        }
    }

    private func voiceTier(_ voice: AVSpeechSynthesisVoice) -> Int {
        let id = voice.identifier.lowercased()
        if id.contains("premium") { return 0 }
        if id.contains("enhanced") { return 1 }
        return 2
    }

    private func voiceTierLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let id = voice.identifier.lowercased()
        if id.contains("premium") { return " ⭐️ Premium" }
        if id.contains("enhanced") { return " ✦ Enhanced" }
        return ""
    }

    // MARK: - Test Connection

    // MARK: - Test Connection

    private func runTest() async {
        isTesting = true
        testResult = nil
        let service = testService ?? WebhookTestService(settings: settings)
        testResult = await service.testConnection()
        isTesting = false
    }
}

// MARK: - Speech Finish Monitor

/// Lightweight AVSpeechSynthesizerDelegate that fires a callback when speech finishes.
private final class SpeechFinishMonitor: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: SettingsManager(defaults: UserDefaults(suiteName: "preview") ?? .standard), testService: nil)
    }
}
