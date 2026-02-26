import SwiftUI
import Foundation

// MARK: - Status

enum VoicePairingStatus: Equatable {
    case idle
    case connecting
    case awaitingApproval
    case paired
    case failed(String)
}

// MARK: - ViewModel

@MainActor
final class VoicePairingViewModel: ObservableObject, GatewayConnectionDelegate {

    @Published private(set) var status: VoicePairingStatus = .idle
    @Published private(set) var nodeId: String = ""
    @Published private(set) var publicKeyFingerprint: String = ""

    private let pairingManager: NodePairingManager
    private let gateway: GatewayConnection

    init() {
        let mgr = NodePairingManager(keychain: RealKeychain())
        let conn = GatewayConnection(
            pairingManager: mgr,
            webSocketFactory: URLSessionWebSocketFactory(),
            networkMonitor: NWNetworkMonitor()
        )
        self.pairingManager = mgr
        self.gateway = conn
        conn.delegate = self

        // Pre-load identity so we can show the node ID before connecting
        if let identity = try? mgr.generateIdentity() {
            self.nodeId = identity.nodeId
            self.publicKeyFingerprint = String(identity.publicKeyBase64.prefix(16))
        }
    }

    // MARK: - Actions

    func requestPairing() {
        guard let url = SettingsManager.shared.voiceWebSocketURL else {
            status = .failed("Gateway URL not configured. Add it in Settings.")
            return
        }
        status = .connecting
        gateway.connect(to: url)
    }

    // MARK: - GatewayConnectionDelegate

    nonisolated func gatewayDidConnect() {
        Task { @MainActor in
            self.status = .awaitingApproval
            try? await self.gateway.sendPairRequest()
        }
    }

    nonisolated func gatewayDidDisconnect() {
        Task { @MainActor in
            if self.status == .connecting {
                self.status = .failed("Disconnected from gateway")
            }
        }
    }

    nonisolated func gatewayDidReceiveEvent(_ event: String, payload: [String: Any]) {
        Task { @MainActor in
            // Accept a token from any pairing-related event
            if let token = payload["token"] as? String, !token.isEmpty {
                try? self.pairingManager.storeToken(token)
                self.status = .paired
            }
        }
    }

    nonisolated func gatewayDidFailWithError(_ error: GatewayConnectionError) {
        Task { @MainActor in
            self.status = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

struct VoicePairingView: View {

    @StateObject private var viewModel = VoicePairingViewModel()
    var onPaired: (() -> Void)?

    private func generateDebugInfo() -> String {
        let url = SettingsManager.shared.voiceWebSocketURL?.absoluteString ?? "NULL"
        let hostname = SettingsManager.shared.hostname
        let tokenStatus = SettingsManager.shared.gatewayToken.isEmpty ? "EMPTY" : "Set (\(SettingsManager.shared.gatewayToken.count) chars)"
        let status = String(describing: viewModel.status)
        
        return """
        🔍 ZAAP VOICE DEBUG INFO
        URL: \(url)
        Hostname: \(hostname)
        Gateway Token: \(tokenStatus)
        Status: \(status)
        Node ID: \(viewModel.nodeId)
        Key Fingerprint: \(viewModel.publicKeyFingerprint)
        """
    }

    var body: some View {
        VStack(spacing: 24) {
            // DEBUG: Show connection details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("🔍 DEBUG CONNECTION INFO")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Copy") {
                        let debugInfo = generateDebugInfo()
                        UIPasteboard.general.string = debugInfo
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                }
                
                if let url = SettingsManager.shared.voiceWebSocketURL {
                    Text("URL: \(url.absoluteString)")
                        .font(.caption.monospaced())
                        .foregroundColor(.blue)
                } else {
                    Text("URL: ❌ NULL - voiceWebSocketURL is nil")
                        .font(.caption.monospaced())
                        .foregroundColor(.red)
                }
                
                Text("Hostname: \(SettingsManager.shared.hostname)")
                    .font(.caption.monospaced())
                    .foregroundColor(.blue)
                
                Text("Gateway Token: \(SettingsManager.shared.gatewayToken.isEmpty ? "❌ EMPTY" : "✅ Set (\(SettingsManager.shared.gatewayToken.count) chars)")")
                    .font(.caption.monospaced())
                    .foregroundColor(SettingsManager.shared.gatewayToken.isEmpty ? .red : .green)
                
                Text("Status: \(String(describing: viewModel.status))")
                    .font(.caption.monospaced())
                    .foregroundColor(.purple)
                
                Text("⚠️ NO iOS CONNECTION ATTEMPTS in gateway logs!")
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()

            Image(systemName: "link.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Pair with Gateway")
                .font(.largeTitle)
                .fontWeight(.bold)

            if !viewModel.nodeId.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Node ID", systemImage: "person.badge.key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.nodeId)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Label("Key fingerprint", systemImage: "key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    Text(viewModel.publicKeyFingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Text("To enable voice, approve this device on your gateway:\n\nopenclaw nodes pending\nopenclaw nodes approve <id>")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            statusView

            Button(action: { viewModel.requestPairing() }) {
                HStack {
                    if viewModel.status == .connecting || viewModel.status == .awaitingApproval {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text(buttonLabel)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(buttonDisabled ? Color.secondary : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(buttonDisabled)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onChange(of: viewModel.status) { _, newStatus in
            if newStatus == .paired {
                onPaired?()
            }
        }
    }

    private var buttonDisabled: Bool {
        switch viewModel.status {
        case .connecting, .awaitingApproval, .paired: return true
        default: return false
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .connecting:
            Label("Connecting to gateway...", systemImage: "network")
                .foregroundColor(.blue)
        case .awaitingApproval:
            Label("Awaiting approval on gateway...", systemImage: "clock")
                .foregroundColor(.orange)
        case .paired:
            Label("Paired!", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var buttonLabel: String {
        switch viewModel.status {
        case .idle: return "Request Pairing"
        case .connecting: return "Connecting..."
        case .awaitingApproval: return "Awaiting Approval..."
        case .paired: return "Paired!"
        case .failed: return "Try Again"
        }
    }
}
