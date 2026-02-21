import XCTest
@testable import Zaap

// MARK: - Test Doubles

final class MockWebSocketTask: WebSocketTaskProtocol {
    var sentMessages: [URLSessionWebSocketTask.Message] = []
    var receivedMessages: [URLSessionWebSocketTask.Message] = []
    var resumeCalled = false
    var cancelCalled = false
    var cancelCode: URLSessionWebSocketTask.CloseCode?
    var shouldThrowOnReceive: Error?

    private var receiveIndex = 0
    private var receiveContinuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if let error = shouldThrowOnReceive {
            throw error
        }
        if receiveIndex < receivedMessages.count {
            let msg = receivedMessages[receiveIndex]
            receiveIndex += 1
            return msg
        }
        // Wait for messages to be enqueued
        return try await withCheckedThrowingContinuation { continuation in
            self.receiveContinuation = continuation
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelCalled = true
        cancelCode = closeCode
        receiveContinuation?.resume(throwing: CancellationError())
        receiveContinuation = nil
    }

    func resume() {
        resumeCalled = true
    }

    /// Enqueue a message for the receive loop to pick up.
    func enqueueMessage(_ json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let msg = URLSessionWebSocketTask.Message.data(data)
        if let cont = receiveContinuation {
            receiveContinuation = nil
            cont.resume(returning: msg)
        } else {
            receivedMessages.append(msg)
        }
    }

    /// Simulate a disconnect error.
    func simulateDisconnect() {
        receiveContinuation?.resume(throwing: URLError(.networkConnectionLost))
        receiveContinuation = nil
    }

    /// Extract the JSON from a sent message.
    func sentJSON(at index: Int) -> [String: Any]? {
        guard index < sentMessages.count else { return nil }
        let msg = sentMessages[index]
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = s.data(using: .utf8) ?? Data()
        @unknown default: return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

final class MockWebSocketFactory: WebSocketFactory {
    var lastCreatedTask: MockWebSocketTask?
    var taskToReturn: MockWebSocketTask?

    func createWebSocketTask(with url: URL) -> WebSocketTaskProtocol {
        let task = taskToReturn ?? MockWebSocketTask()
        lastCreatedTask = task
        return task
    }
}

final class MockNetworkMonitor: NetworkPathMonitoring {
    var isConnected: Bool = true
    var startCalled = false
    var stopCalled = false
    var pathUpdateHandler: ((Bool) -> Void)?

    func start(onPathUpdate: @escaping (Bool) -> Void) {
        startCalled = true
        pathUpdateHandler = onPathUpdate
    }

    func stop() {
        stopCalled = true
    }

    func simulateNetworkChange(connected: Bool) {
        isConnected = connected
        pathUpdateHandler?(connected)
    }
}

final class MockGatewayDelegate: GatewayConnectionDelegate {
    var connectCalled = false
    var disconnectCalled = false
    var receivedEvents: [(event: String, payload: [String: Any])] = []
    var errors: [GatewayConnectionError] = []

    func gatewayDidConnect() {
        connectCalled = true
    }

    func gatewayDidDisconnect() {
        disconnectCalled = true
    }

    func gatewayDidReceiveEvent(_ event: String, payload: [String: Any]) {
        receivedEvents.append((event: event, payload: payload))
    }

    func gatewayDidFailWithError(_ error: GatewayConnectionError) {
        errors.append(error)
    }
}

// MARK: - Tests

final class GatewayConnectionTests: XCTestCase {

    var mockKeychain: MockKeychainAccess!
    var pairingManager: NodePairingManager!
    var mockWSFactory: MockWebSocketFactory!
    var mockNetworkMonitor: MockNetworkMonitor!
    var mockDelegate: MockGatewayDelegate!
    var connection: GatewayConnection!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainAccess()
        pairingManager = NodePairingManager(keychain: mockKeychain)
        mockWSFactory = MockWebSocketFactory()
        mockNetworkMonitor = MockNetworkMonitor()
        mockDelegate = MockGatewayDelegate()

        connection = GatewayConnection(
            pairingManager: pairingManager,
            webSocketFactory: mockWSFactory,
            networkMonitor: mockNetworkMonitor
        )
        connection.delegate = mockDelegate
    }

    override func tearDown() {
        connection.disconnect()
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsDisconnected() {
        XCTAssertEqual(connection.state, .disconnected)
    }

    // MARK: - Connect

    func testConnectCreatesWebSocketTask() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)

        XCTAssertNotNil(mockWSFactory.lastCreatedTask)
    }

    func testConnectResumesWebSocketTask() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)

        XCTAssertTrue(mockWSFactory.lastCreatedTask!.resumeCalled)
    }

    func testConnectSetsStateToConnecting() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)

        XCTAssertEqual(connection.state, .connecting)
    }

    func testConnectIsNoOpWhenAlreadyConnecting() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)
        let firstTask = mockWSFactory.lastCreatedTask

        connection.connect(to: url)

        XCTAssertTrue(mockWSFactory.lastCreatedTask === firstTask)
    }

    // MARK: - Disconnect

    func testDisconnectCancelsWebSocket() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)
        let task = mockWSFactory.lastCreatedTask!

        connection.disconnect()

        XCTAssertTrue(task.cancelCalled)
        XCTAssertEqual(task.cancelCode, .normalClosure)
    }

    func testDisconnectSetsStateToDisconnected() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)

        connection.disconnect()

        XCTAssertEqual(connection.state, .disconnected)
    }

    func testDisconnectNotifiesDelegate() {
        let url = URL(string: "wss://192.168.1.100:18789")!
        connection.connect(to: url)

        connection.disconnect()

        XCTAssertTrue(mockDelegate.disconnectCalled)
    }

    // MARK: - Challenge Handling

    func testReceivingChallengeSetsChallengedState() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "event", "event": "connect.challenge", "payload": ["nonce": "test-nonce"]])
        ]
        // After challenge, block on receive
        mockWSFactory.taskToReturn = mockTask

        _ = try pairingManager.generateIdentity()
        try pairingManager.storeToken("test-token")

        connection.connect(to: url)

        // Give async receive loop time to process
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(connection.state, .challenged)
    }

    func testChallengeResponseIncludesDeviceSignature() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "event", "event": "connect.challenge", "payload": ["nonce": "test-nonce-123"]])
        ]
        mockWSFactory.taskToReturn = mockTask

        let identity = try pairingManager.generateIdentity()
        try pairingManager.storeToken("my-token")

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 200_000_000)

        // The connect response should be the first sent message
        XCTAssertGreaterThanOrEqual(mockTask.sentMessages.count, 1)

        let json = mockTask.sentJSON(at: 0)
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["type"] as? String, "req")
        XCTAssertEqual(json?["method"] as? String, "connect")

        let params = json?["params"] as? [String: Any]
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["role"] as? String, "node")

        // Auth token is now nested under "auth"
        let auth = params?["auth"] as? [String: Any]
        XCTAssertEqual(auth?["token"] as? String, "my-token")

        let device = params?["device"] as? [String: Any]
        XCTAssertEqual(device?["id"] as? String, identity.nodeId)
        XCTAssertEqual(device?["publicKey"] as? String, identity.publicKeyBase64)
        XCTAssertNotNil(device?["signature"] as? String)
        XCTAssertNotNil(device?["signedAt"] as? Int)
        XCTAssertEqual(device?["nonce"] as? String, "test-nonce-123")

        let client = params?["client"] as? [String: Any]
        XCTAssertEqual(client?["id"] as? String, "zaap")
        XCTAssertEqual(client?["mode"] as? String, "node")
        XCTAssertEqual(client?["platform"] as? String, "ios")

        let caps = params?["caps"] as? [String]
        XCTAssertEqual(caps, ["voice"])
    }

    func testChallengeWithKeychainErrorReportsNoIdentity() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "event", "event": "connect.challenge", "payload": ["nonce": "test"]])
        ]
        mockWSFactory.taskToReturn = mockTask

        // Make keychain throw so generateIdentity fails
        mockKeychain.shouldThrow = NodePairingError.keychainError("simulated")
        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(mockDelegate.errors.contains(.noIdentity))
    }

    func testChallengeWithoutNonceReportsError() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "event", "event": "connect.challenge", "payload": [:] as [String: Any]])
        ]
        mockWSFactory.taskToReturn = mockTask

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockDelegate.errors.count, 1)
        if case .challengeFailed = mockDelegate.errors.first! {
            // expected
        } else {
            XCTFail("Expected challengeFailed error")
        }
    }

    // MARK: - Hello-Ok Handling

    func testHelloOkSetsConnectedState() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "res", "id": "1", "ok": true, "payload": ["type": "hello-ok"]])
        ]
        mockWSFactory.taskToReturn = mockTask

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(connection.state, .connected)
    }

    func testHelloOkNotifiesDelegate() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "res", "id": "1", "ok": true, "payload": ["type": "hello-ok"]])
        ]
        mockWSFactory.taskToReturn = mockTask

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(mockDelegate.connectCalled)
    }

    // MARK: - Message Routing

    func testRoutesNodeInvokeRequestToDelegate() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "res", "id": "1", "ok": true, "payload": ["type": "hello-ok"]]),
            makeMessage(["type": "event", "event": "node.invoke.request", "payload": ["command": "camera_snap"]])
        ]
        mockWSFactory.taskToReturn = mockTask

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodeEvents = mockDelegate.receivedEvents.filter { $0.event == "node.invoke.request" }
        XCTAssertEqual(nodeEvents.count, 1)
        XCTAssertEqual(nodeEvents.first?.payload["command"] as? String, "camera_snap")
    }

    func testRoutesChatEventToDelegate() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            makeMessage(["type": "res", "id": "1", "ok": true, "payload": ["type": "hello-ok"]]),
            makeMessage(["type": "event", "event": "chat.event", "payload": ["text": "Hello world"]])
        ]
        mockWSFactory.taskToReturn = mockTask

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 200_000_000)

        let chatEvents = mockDelegate.receivedEvents.filter { $0.event == "chat.event" }
        XCTAssertEqual(chatEvents.count, 1)
    }

    // MARK: - Backoff Calculation

    func testBackoffDelayForAttempt0Is1Second() {
        XCTAssertEqual(GatewayConnection.backoffDelay(forAttempt: 0), 1.0)
    }

    func testBackoffDelayForAttempt1Is2Seconds() {
        XCTAssertEqual(GatewayConnection.backoffDelay(forAttempt: 1), 2.0)
    }

    func testBackoffDelayForAttempt2Is4Seconds() {
        XCTAssertEqual(GatewayConnection.backoffDelay(forAttempt: 2), 4.0)
    }

    func testBackoffDelayForAttempt3Is8Seconds() {
        XCTAssertEqual(GatewayConnection.backoffDelay(forAttempt: 3), 8.0)
    }

    func testBackoffDelayCapsAt30Seconds() {
        XCTAssertEqual(GatewayConnection.backoffDelay(forAttempt: 5), 30.0)
        XCTAssertEqual(GatewayConnection.backoffDelay(forAttempt: 10), 30.0)
    }

    // MARK: - Network Monitor

    func testNetworkMonitorStartedOnInit() {
        XCTAssertTrue(mockNetworkMonitor.startCalled)
    }

    // MARK: - Send Event

    func testSendEventThrowsWhenNotConnected() async {
        do {
            try await connection.sendEvent("test", payload: [:])
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(error as? GatewayConnectionError, .connectionFailed("Not connected"))
        }
    }

    // MARK: - Invalid Message

    func testInvalidJSONReportsError() async throws {
        let url = URL(string: "wss://192.168.1.100:18789")!
        let mockTask = MockWebSocketTask()
        mockTask.receivedMessages = [
            URLSessionWebSocketTask.Message.string("not json at all")
        ]
        mockWSFactory.taskToReturn = mockTask

        connection.connect(to: url)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(mockDelegate.errors.contains(.invalidMessage))
    }

    // MARK: - Helpers

    private func makeMessage(_ json: [String: Any]) -> URLSessionWebSocketTask.Message {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return .data(data)
    }
}
