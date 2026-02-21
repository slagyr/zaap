import Foundation

// MARK: - Pairing Connection Status

enum PairingConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
}

// MARK: - PairingViewModel

/// Manages gateway pairing UI state: enter address, connect/pair, unpair.
@MainActor
@Observable
final class PairingViewModel {

    var gatewayAddress: String = ""
    private(set) var isPaired: Bool = false
    private(set) var isConnecting: Bool = false
    private(set) var connectionStatus: PairingConnectionStatus = .disconnected

    private let pairingManager: NodePairingManager
    private let gateway: GatewayConnecting

    init(pairingManager: NodePairingManager, gateway: GatewayConnecting) {
        self.pairingManager = pairingManager
        self.gateway = gateway
        self.isPaired = pairingManager.isPaired

        if let savedURL = pairingManager.loadGatewayURL() {
            self.gatewayAddress = savedURL.absoluteString
        }

        // Set ourselves as delegate to receive connection events
        gateway.delegate = self
    }

    // MARK: - Actions

    func connect() {
        let url: URL
        if gatewayAddress.hasPrefix("wss://") || gatewayAddress.hasPrefix("ws://") {
            url = URL(string: gatewayAddress)!
        } else {
            url = URL(string: "wss://\(gatewayAddress):18789")!
        }

        isConnecting = true
        connectionStatus = .connecting

        // Generate identity if needed
        _ = try? pairingManager.generateIdentity()
        try? pairingManager.storeGatewayURL(url)

        gateway.connect(to: url)
    }

    func unpair() {
        gateway.disconnect()
        pairingManager.clearPairing()
        isPaired = false
        connectionStatus = .disconnected
        gatewayAddress = ""
    }
}

// MARK: - GatewayConnectionDelegate

extension PairingViewModel: GatewayConnectionDelegate {
    nonisolated func gatewayDidConnect() {
        Task { @MainActor in
            self.isPaired = true
            self.isConnecting = false
            self.connectionStatus = .connected
        }
    }

    nonisolated func gatewayDidDisconnect() {
        Task { @MainActor in
            self.isConnecting = false
            if self.connectionStatus != .disconnected {
                self.connectionStatus = .disconnected
            }
        }
    }

    nonisolated func gatewayDidReceiveEvent(_ event: String, payload: [String: Any]) {
        // Events handled by VoiceChatCoordinator
    }

    nonisolated func gatewayDidFailWithError(_ error: GatewayConnectionError) {
        Task { @MainActor in
            self.isConnecting = false
            self.connectionStatus = .disconnected
        }
    }
}
