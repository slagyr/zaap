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
        print("🔧 [DEBUG] requestPairing() called")
        
        guard let url = SettingsManager.shared.voiceWebSocketURL else {
            print("❌ [DEBUG] Gateway URL is nil!")
            status = .failed("Gateway URL not configured. Add it in Settings.")
            return
        }
        
        print("✅ [DEBUG] Gateway URL: \(url.absoluteString)")
        print("🔧 [DEBUG] Setting status to .connecting")
        status = .connecting
        
        print("🔧 [DEBUG] Calling gateway.connect(to: \(url.absoluteString))")
        gateway.connect(to: url)
        print("🔧 [DEBUG] gateway.connect() call completed")
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

    @State private var copiedDeviceId = false

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
                    // Device ID with copy button
                    VStack(spacing: 6) {
                        Label("Device ID", systemImage: "cpu")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 10) {
                            Text(viewModel.nodeId)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = viewModel.nodeId
                                copiedDeviceId = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedDeviceId = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedDeviceId ? "checkmark" : "doc.on.doc")
                                    Text(copiedDeviceId ? "Copied" : "Copy")
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(copiedDeviceId ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                                .foregroundColor(copiedDeviceId ? .green : .blue)
                                .cornerRadius(6)
                            }
                        }
                    }

                    Divider()

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

            Text("To enable voice, approve this device on your gateway:\n\nopenclaw nodes pending\nopenclaw nodes approve <id>")
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
