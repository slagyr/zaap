import Foundation

// MARK: - Protocols for Dependency Injection

/// Abstracts URLSessionWebSocketTask for testability.
protocol WebSocketTaskProtocol: AnyObject {
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func resume()
}

extension URLSessionWebSocketTask: WebSocketTaskProtocol {}

/// Factory for creating WebSocket tasks.
protocol WebSocketFactory {
    func createWebSocketTask(with url: URL) -> WebSocketTaskProtocol
}

/// Monitors network path status.
protocol NetworkPathMonitoring {
    var isConnected: Bool { get }
    func start(onPathUpdate: @escaping (Bool) -> Void)
    func stop()
}

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case challenged
    case connected
    case reconnecting(attempt: Int)
}

// MARK: - Gateway Message Types

/// Incoming JSON-RPC style messages from the gateway.
struct GatewayMessage {
    let type: String
    let method: String?
    let id: String?
    let params: [String: Any]?
    let result: [String: Any]?

    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        self.type = type
        self.method = json["method"] as? String
        self.id = json["id"] as? String
        self.params = json["params"] as? [String: Any]
        self.result = json["result"] as? [String: Any]
    }
}

/// Delegate for receiving gateway events.
protocol GatewayConnectionDelegate: AnyObject {
    func gatewayDidConnect()
    func gatewayDidDisconnect()
    func gatewayDidReceiveEvent(_ event: String, payload: [String: Any])
    func gatewayDidFailWithError(_ error: GatewayConnectionError)
}

enum GatewayConnectionError: Error, Equatable {
    case noIdentity
    case invalidMessage
    case connectionFailed(String)
    case challengeFailed(String)
}

// MARK: - GatewayConnection

/// WebSocket client for connecting to the OpenClaw gateway as a paired node.
///
/// Handles the connect handshake (challenge-response with device signature),
/// routes incoming messages by type, and reconnects with exponential backoff.
final class GatewayConnection {

    // MARK: - Public State

    private(set) var state: ConnectionState = .disconnected

    weak var delegate: GatewayConnectionDelegate?

    // MARK: - Configuration

    static let maxBackoffSeconds: TimeInterval = 30
    static let initialBackoffSeconds: TimeInterval = 1

    // MARK: - Dependencies

    private let pairingManager: NodePairingManager
    private let webSocketFactory: WebSocketFactory
    private let networkMonitor: NetworkPathMonitoring

    // MARK: - Internal State

    private var webSocket: WebSocketTaskProtocol?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var gatewayURL: URL?
    private var intentionalDisconnect = false

    init(pairingManager: NodePairingManager,
         webSocketFactory: WebSocketFactory,
         networkMonitor: NetworkPathMonitoring) {
        self.pairingManager = pairingManager
        self.webSocketFactory = webSocketFactory
        self.networkMonitor = networkMonitor

        self.networkMonitor.start { [weak self] connected in
            guard let self = self else { return }
            if connected && self.state == .disconnected && self.gatewayURL != nil && !self.intentionalDisconnect {
                self.attemptReconnect()
            }
        }
    }

    // MARK: - Connect / Disconnect

    func connect(to url: URL) {
        guard state == .disconnected else { return }
        intentionalDisconnect = false
        gatewayURL = url
        reconnectAttempt = 0
        performConnect(to: url)
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        state = .disconnected
        delegate?.gatewayDidDisconnect()
    }

    // MARK: - Send

    func sendEvent(_ event: String, payload: [String: Any]) async throws {
        guard state == .connected, let ws = webSocket else {
            throw GatewayConnectionError.connectionFailed("Not connected")
        }

        let message: [String: Any] = [
            "type": "request",
            "method": "node.event",
            "id": UUID().uuidString,
            "params": [
                "event": event,
                "payloadJSON": jsonString(payload) ?? "{}"
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.data(data))
    }

    func sendVoiceTranscript(_ text: String, sessionKey: String) async throws {
        try await sendEvent("voice.transcript", payload: [
            "text": text,
            "sessionKey": sessionKey,
            "eventId": UUID().uuidString
        ])
    }

    // MARK: - Backoff Calculation

    /// Calculate backoff delay for a given attempt number.
    /// Uses exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped).
    static func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let delay = initialBackoffSeconds * pow(2.0, Double(attempt))
        return min(delay, maxBackoffSeconds)
    }

    // MARK: - Private: Connection Flow

    private func performConnect(to url: URL) {
        state = .connecting
        let ws = webSocketFactory.createWebSocketTask(with: url)
        self.webSocket = ws
        ws.resume()
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                guard let ws = self.webSocket else { break }
                do {
                    let message = try await ws.receive()
                    self.handleRawMessage(message)
                } catch {
                    if !Task.isCancelled && !self.intentionalDisconnect {
                        self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleRawMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            data = s.data(using: .utf8) ?? Data()
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            delegate?.gatewayDidFailWithError(.invalidMessage)
            return
        }

        let type = json["type"] as? String ?? ""
        let method = json["method"] as? String

        if type == "challenge" || method == "connect.challenge" {
            handleChallenge(json)
        } else if type == "hello-ok" || method == "hello-ok" {
            handleHelloOk()
        } else if type == "event" || method?.hasPrefix("node.") == true || method?.hasPrefix("chat.") == true {
            let event = method ?? (json["event"] as? String) ?? type
            let params = json["params"] as? [String: Any] ?? json
            delegate?.gatewayDidReceiveEvent(event, payload: params)
        } else {
            // Route unknown messages as generic events
            let event = method ?? type
            delegate?.gatewayDidReceiveEvent(event, payload: json)
        }
    }

    private func handleChallenge(_ json: [String: Any]) {
        state = .challenged

        let nonce: String
        if let params = json["params"] as? [String: Any], let n = params["nonce"] as? String {
            nonce = n
        } else if let n = json["nonce"] as? String {
            nonce = n
        } else {
            delegate?.gatewayDidFailWithError(.challengeFailed("No nonce in challenge"))
            return
        }

        do {
            let identity = try pairingManager.generateIdentity()
            let sig = try pairingManager.signChallenge(nonce: nonce)
            let token = pairingManager.loadToken() ?? ""

            let connectMessage: [String: Any] = [
                "type": "request",
                "method": "connect",
                "id": UUID().uuidString,
                "params": [
                    "minProtocol": 1,
                    "maxProtocol": 1,
                    "client": [
                        "id": "zaap",
                        "mode": "node",
                        "platform": "iOS",
                        "version": "1.0"
                    ] as [String: Any],
                    "caps": ["voice"],
                    "device": [
                        "id": identity.nodeId,
                        "publicKey": identity.publicKeyBase64,
                        "signature": sig.signature,
                        "signedAt": sig.signedAt,
                        "nonce": nonce
                    ] as [String: Any],
                    "token": token,
                    "role": "node"
                ] as [String: Any]
            ]

            let data = try JSONSerialization.data(withJSONObject: connectMessage)
            Task {
                do {
                    try await webSocket?.send(.data(data))
                } catch {
                    delegate?.gatewayDidFailWithError(.challengeFailed(error.localizedDescription))
                }
            }
        } catch {
            delegate?.gatewayDidFailWithError(.noIdentity)
        }
    }

    private func handleHelloOk() {
        state = .connected
        reconnectAttempt = 0
        delegate?.gatewayDidConnect()
    }

    // MARK: - Private: Reconnection

    private func handleDisconnect() {
        webSocket = nil
        receiveTask = nil
        if !intentionalDisconnect {
            state = .disconnected
            delegate?.gatewayDidDisconnect()
            attemptReconnect()
        }
    }

    private func attemptReconnect() {
        guard let url = gatewayURL, !intentionalDisconnect else { return }
        guard state == .disconnected else { return }

        let delay = Self.backoffDelay(forAttempt: reconnectAttempt)
        state = .reconnecting(attempt: reconnectAttempt)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            self.reconnectAttempt += 1
            self.state = .disconnected
            self.performConnect(to: url)
        }
    }

    // MARK: - Helpers

    private func jsonString(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
