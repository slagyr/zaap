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
    @Published private(set) var approvalRequestId: String = ""

    private let pairingManager: NodePairingManager
    private let gateway: GatewayConnection

    init() {
        let mgr = NodePairingManager()
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
        // Always disconnect first to reset state (may be stuck in reconnecting)
        gateway.disconnect()
        connect(to: url)
    }

    private func connect(to url: URL) {
        gateway.connect(to: url)
    }

    // MARK: - GatewayConnectionDelegate

    nonisolated func gatewayDidConnect() {
        // hello-ok received — token already stored by GatewayConnection.handleHelloOk
        Task { @MainActor in
            self.status = .paired
        }
    }

    nonisolated func gatewayDidDisconnect() {
        Task { @MainActor in
            // Only reset if still actively trying (not awaiting approval — we poll in that case)
            if self.status == .connecting {
                self.status = .failed("Disconnected from gateway")
            }
        }
    }

    nonisolated func gatewayDidReceiveEvent(_ event: String, payload: [String: Any]) {
        // Not needed for new pairing flow — token arrives via hello-ok in GatewayConnection
    }

    nonisolated func gatewayDidFailWithError(_ error: GatewayConnectionError) {
        Task { @MainActor in
            if case .challengeFailed(let msg) = error, msg.hasPrefix("pairing_required") {
                // Extract requestId if present (format: "pairing_required:<requestId>")
                let parts = msg.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    self.approvalRequestId = String(parts[1])
                }
                // Stop the gateway's built-in reconnect loop so we control retry timing
                self.gateway.disconnect()
                self.status = .awaitingApproval
                guard let url = SettingsManager.shared.voiceWebSocketURL else { return }
                // Poll every 5s until approved
                while self.status == .awaitingApproval {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if self.status == .awaitingApproval {
                        self.connect(to: url)
                    }
                }
            } else {
                self.status = .failed(error.localizedDescription)
            }
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
            Spacer()

            Image(systemName: "link.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Pair with Gateway")
                .font(.largeTitle)
                .fontWeight(.bold)

            if !viewModel.nodeId.isEmpty {
                VStack(spacing: 12) {
                    // Key fingerprint
                    VStack(spacing: 4) {
                        Label("Key Fingerprint", systemImage: "key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(viewModel.publicKeyFingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Text("To enable voice, approve this device on your gateway:\n\nopenclaw devices list\nopenclaw devices approve <id>")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            statusView

            Button(action: { 
                print("🚨 [CRITICAL] BUTTON TAPPED!")
                viewModel.requestPairing() 
            }) {
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
            VStack(spacing: 6) {
                Label("Awaiting approval on gateway...", systemImage: "clock")
                    .foregroundColor(.orange)
                if !viewModel.approvalRequestId.isEmpty {
                    Text("openclaw devices approve \(viewModel.approvalRequestId)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                }
            }
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
