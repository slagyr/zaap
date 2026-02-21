import SwiftUI

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
    @State private var isTesting = false
    @State private var testResult: WebhookTestService.TestResult?
    @State private var locationSendStatus: SendNowStatus = .idle
    @State private var sleepSendStatus: SendNowStatus = .idle
    @State private var workoutSendStatus: SendNowStatus = .idle
    @State private var heartRateSendStatus: SendNowStatus = .idle
    @State private var activitySendStatus: SendNowStatus = .idle

    #if targetEnvironment(simulator)
    @StateObject private var seeder = HealthDataSeeder()
    @AppStorage("settings.devMode") private var devMode: Bool = true
    #endif

    var body: some View {
        Form {
            #if targetEnvironment(simulator)
            Section {
                Toggle("Use development config?", isOn: $devMode)
                    .onChange(of: devMode) { _, isDev in
                        applyDevMode(isDev)
                    }

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
            } header: {
                Text("Developer")
            } footer: {
                Text(devMode
                     ? "Dev: localhost:8788"
                     : "Prod: REDACTED_HOSTNAME")
                    .font(.caption)
            }
            #endif

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
                            TextField("Bearer Token", text: $settings.authToken)
                        } else {
                            SecureField("Bearer Token", text: $settings.authToken)
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
            } header: {
                Text("Server")
            } footer: {
                if settings.hostname.isEmpty {
                    Text("Enter your OpenClaw gateway hostname (e.g. myhost.ts.net)")
                } else {
                    Text("Sends to: https://\(settings.hostname)/hooks/…")
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
            #if targetEnvironment(simulator)
            applyDevMode(devMode)
            #endif
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

    // MARK: - Developer (Simulator)

    #if targetEnvironment(simulator)
    private func applyDevMode(_ isDev: Bool) {
        if isDev {
            settings.webhookURL = "localhost:8788"
            settings.authToken = "mock"
        } else {
            settings.webhookURL = "REDACTED_HOSTNAME"
            settings.authToken = "REDACTED_HOOKS_TOKEN"
        }
        // Voice WebSocket always uses the real gateway regardless of dev/prod toggle.
        settings.voiceGatewayHostname = "REDACTED_HOSTNAME"
    }
    #endif

    // MARK: - Test Connection

    private func runTest() async {
        isTesting = true
        testResult = nil
        let service = testService ?? WebhookTestService(settings: settings)
        testResult = await service.testConnection()
        isTesting = false
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: SettingsManager(defaults: UserDefaults(suiteName: "preview") ?? .standard), testService: nil)
    }
}
