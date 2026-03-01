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

    @Published var status: VoicePairingStatus = .idle
    @Published private(set) var nodeId: String = ""
    @Published private(set) var publicKeyFingerprint: String = ""
    @Published private(set) var approvalRequestId: String = ""
    @Published private(set) var currentRole: String = "node"

    private let pairingManager: NodePairingManager
    private let gatewayFactory: GatewayFactory?
    private var gateway: GatewayConnecting
    private static let rolesToPair: [ConnectionRole] = [.node, .operator]

    /// Legacy init: single gateway, pairs one role only (backward compat for existing tests).
    init(pairingManager: NodePairingManager? = nil, gateway: GatewayConnecting? = nil) {
        let mgr = pairingManager ?? NodePairingManager()
        let conn: GatewayConnecting
        if let gateway = gateway {
            conn = gateway
        } else {
            conn = GatewayConnection(
                pairingManager: mgr,
                webSocketFactory: URLSessionWebSocketFactory(),
                networkMonitor: NWNetworkMonitor()
            )
        }
        self.pairingManager = mgr
        self.gateway = conn
        self.gatewayFactory = nil
        conn.delegate = self

        loadIdentity(mgr)
    }

    /// Dual-role init: uses a factory to create gateways per role.
    init(pairingManager: NodePairingManager, gatewayFactory: GatewayFactory) {
        self.pairingManager = pairingManager
        self.gatewayFactory = gatewayFactory

        // Determine which role needs pairing first
        let nextRole = Self.nextUnpairedRole(pairingManager: pairingManager)
        if let role = nextRole {
            self.currentRole = role.name
            self.gateway = gatewayFactory.createGateway(role: role)
        } else {
            // Both roles already paired
            self.currentRole = "operator"
            self.gateway = gatewayFactory.createGateway(role: .operator)
            self.status = .paired
        }
        self.gateway.delegate = self

        loadIdentity(pairingManager)
    }

    private func loadIdentity(_ mgr: NodePairingManager) {
        if let identity = try? mgr.generateIdentity() {
            self.nodeId = identity.nodeId
            self.publicKeyFingerprint = String(identity.publicKeyBase64.prefix(16))
        }
    }

    /// Find the next role that doesn't have a token yet.
    private static func nextUnpairedRole(pairingManager: NodePairingManager) -> ConnectionRole? {
        for role in rolesToPair {
            if pairingManager.loadToken(forRole: role.name) == nil {
                return role
            }
        }
        return nil
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

    /// Advance to the next unpaired role, or finish if all roles are paired.
    private func advanceToNextRole() {
        guard let factory = gatewayFactory else {
            // Legacy single-gateway mode — just mark paired
            status = .paired
            return
        }

        if let nextRole = Self.nextUnpairedRole(pairingManager: pairingManager) {
            // Disconnect the current gateway before creating the next one
            gateway.disconnect()
            currentRole = nextRole.name
            approvalRequestId = ""
            let newGateway = factory.createGateway(role: nextRole)
            self.gateway = newGateway
            newGateway.delegate = self
            status = .connecting
            guard let url = SettingsManager.shared.voiceWebSocketURL else {
                status = .failed("Gateway URL not configured. Add it in Settings.")
                return
            }
            connect(to: url)
        } else {
            // All roles paired
            gateway.disconnect()
            status = .paired
        }
    }

    // MARK: - GatewayConnectionDelegate

    nonisolated func gatewayDidConnect() {
        // hello-ok received — token already stored by GatewayConnection.handleHelloOk
        Task { @MainActor in
            self.advanceToNextRole()
        }
    }

    nonisolated func gatewayDidDisconnect() {
        Task { @MainActor in
            // Don't show error during connecting — the error callback handles pairing_required.
            // Only show disconnect error if we were previously paired/connected.
            if self.status == .paired {
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

    @StateObject private var viewModel: VoicePairingViewModel
    var onPaired: (() -> Void)?

    init(onPaired: (() -> Void)? = nil) {
        let mgr = NodePairingManager()
        let factory = RealGatewayFactory(pairingManager: mgr)
        _viewModel = StateObject(wrappedValue: VoicePairingViewModel(pairingManager: mgr, gatewayFactory: factory))
        self.onPaired = onPaired
    }

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

    private var roleLabel: String {
        viewModel.currentRole == "node" ? "voice" : "operator"
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .connecting:
            Label("Connecting \(roleLabel) to gateway...", systemImage: "network")
                .foregroundColor(.blue)
        case .awaitingApproval:
            VStack(spacing: 6) {
                Label("Awaiting \(roleLabel) approval on gateway...", systemImage: "clock")
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
