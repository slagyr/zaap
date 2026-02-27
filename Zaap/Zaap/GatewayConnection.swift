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
        print("🔧 [GATEWAY] connect(to: \(url.absoluteString)) called")
        print("🔧 [GATEWAY] Current state: \(state)")
        
        guard state == .disconnected else { 
            print("❌ [GATEWAY] Cannot connect - state is not disconnected, current state: \(state)")
            return 
        }
        
        intentionalDisconnect = false
        gatewayURL = url
        reconnectAttempt = 0
        
        print("🔧 [GATEWAY] Calling performConnect(to: \(url.absoluteString))")
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
            "type": "req",
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

    /// Send a node.pair.request directly as a gateway method call (not wrapped in node.event).
    func sendPairRequest() async throws {
        guard let ws = webSocket else {
            throw GatewayConnectionError.connectionFailed("Not connected")
        }
        let identity = try pairingManager.generateIdentity()
        let message: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "node.pair.request",
            "params": [
                "nodeId": identity.nodeId,
                "displayName": "Zaap (iPhone)",
                "platform": "iOS",
                "publicKey": identity.publicKeyBase64,
                "caps": ["voice"]
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.data(data))
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
        print("🔧 [GATEWAY] performConnect(to: \(url.absoluteString)) called")
        state = .connecting
        
        print("🔧 [GATEWAY] Creating WebSocket task with factory")
        let ws = webSocketFactory.createWebSocketTask(with: url)
        self.webSocket = ws
        
        print("🔧 [GATEWAY] Calling ws.resume() to start WebSocket connection")
        ws.resume()
        
        print("🔧 [GATEWAY] Starting receive loop")
        startReceiveLoop()
        
        print("✅ [GATEWAY] performConnect completed, WebSocket should be connecting...")
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
        let event = json["event"] as? String
        let payload = json["payload"] as? [String: Any]

        if type == "event" && event == "connect.challenge" {
            // Protocol: {type:"event", event:"connect.challenge", payload:{nonce, ts}}
            handleChallenge(json)
        } else if type == "res" && (payload?["type"] as? String) == "hello-ok" {
            // Protocol: {type:"res", id, ok:true, payload:{type:"hello-ok", ...}}
            handleHelloOk(payload: payload)
        } else if type == "res", let ok = json["ok"] as? Bool, !ok {
            // Failed response — check for pairing required (1008)
            let error = json["error"] as? [String: Any]
            let code = error?["code"] as? Int ?? 0
            let msg = error?["message"] as? String ?? "Connection failed"
            if code == 1008 {
                // Pairing required: surface to delegate so UI can prompt user to approve
                delegate?.gatewayDidFailWithError(.challengeFailed("pairing_required"))
            } else {
                delegate?.gatewayDidFailWithError(.challengeFailed(msg))
            }
        } else if type == "event" {
            // All other gateway events
            let eventName = event ?? ""
            let params = payload ?? json
            delegate?.gatewayDidReceiveEvent(eventName, payload: params)
        } else if type == "res" {
            // Response to a req — route as event for callers to handle
            let method = json["method"] as? String ?? "response"
            delegate?.gatewayDidReceiveEvent(method, payload: json)
        } else {
            // Fallback: route unknown frames as generic events
            delegate?.gatewayDidReceiveEvent(type, payload: json)
        }
    }

    private func handleChallenge(_ json: [String: Any]) {
        state = .challenged

        // Protocol: nonce lives in payload.nonce
        guard let payloadDict = json["payload"] as? [String: Any],
              let nonce = payloadDict["nonce"] as? String else {
            delegate?.gatewayDidFailWithError(.challengeFailed("No nonce in challenge payload"))
            return
        }

        do {
            let identity = try pairingManager.generateIdentity()

            // Use stored device token if already paired; otherwise use gateway bearer token from settings.
            // Empty token is valid — gateway will respond with 1008 (pairing required) if not yet approved.
            let authToken = pairingManager.loadToken() ?? SettingsManager.shared.gatewayToken

            let sig = try pairingManager.signChallenge(
                nonce: nonce,
                deviceId: identity.nodeId,
                clientId: "zaap-ios",
                clientMode: "operator",
                role: "operator",
                scopes: ["operator.read", "operator.write"],
                token: authToken,
                platform: "ios",
                deviceFamily: "iphone"
            )

            // Protocol: type must be "req" (not "request"), auth in "auth" sub-key.
            let connectMessage: [String: Any] = [
                "type": "req",
                "method": "connect",
                "id": UUID().uuidString,
                "params": [
                    "minProtocol": 3,
                    "maxProtocol": 3,
                    "client": [
                        "id": "zaap-ios",
                        "mode": "operator",
                        "platform": "ios",
                        "deviceFamily": "iphone",
                        "version": "1.0.0"
                    ] as [String: Any],
                    "role": "operator",
                    "scopes": ["operator.read", "operator.write"],
                    "caps": [],
                    "commands": [],
                    "permissions": [:] as [String: Any],
                    "auth": ["token": authToken] as [String: Any],
                    "locale": "en-US",
                    "userAgent": "zaap-ios/1.0.0",
                    "device": [
                        "id": identity.nodeId,
                        "publicKey": identity.publicKeyBase64,
                        "signature": sig.signature,
                        "signedAt": sig.signedAt,
                        "nonce": nonce
                    ] as [String: Any]
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

    private func handleHelloOk(payload: [String: Any]?) {
        state = .connected
        reconnectAttempt = 0

        // If the gateway issued a device token, store it for future connections.
        if let auth = payload?["auth"] as? [String: Any],
           let deviceToken = auth["deviceToken"] as? String,
           !deviceToken.isEmpty {
            try? pairingManager.storeToken(deviceToken)
        }

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
