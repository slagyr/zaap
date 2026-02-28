import XCTest
@testable import Zaap

@MainActor
final class PairingViewModelTests: XCTestCase {

    var mockKeychain: MockKeychainAccess!
    var pairingManager: NodePairingManager!
    var mockGateway: MockGatewayConnecting!
    var viewModel: PairingViewModel!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainAccess()
        pairingManager = NodePairingManager(keychain: mockKeychain)
        mockGateway = MockGatewayConnecting()
        viewModel = PairingViewModel(pairingManager: pairingManager, gateway: mockGateway)
    }

    // MARK: - Initial State

    func testInitialStateShowsUnpairedWhenNoToken() {
        XCTAssertFalse(viewModel.isPaired)
    }

    func testInitialStateShowsPairedWhenTokenExists() throws {
        try pairingManager.storeToken("existing-token")
        let vm = PairingViewModel(pairingManager: pairingManager, gateway: mockGateway)
        XCTAssertTrue(vm.isPaired)
    }

    // MARK: - Gateway Address

    func testGatewayAddressDefaultsToEmpty() {
        XCTAssertEqual(viewModel.gatewayAddress, "")
    }

    func testGatewayAddressLoadsFromPairingManager() throws {
        try pairingManager.storeGatewayURL(URL(string: "wss://myhost.ts.net:18789")!)
        let vm = PairingViewModel(pairingManager: pairingManager, gateway: mockGateway)
        XCTAssertEqual(vm.gatewayAddress, "wss://myhost.ts.net:18789")
    }

    // MARK: - Connect

    func testConnectBuildsURLAndConnects() {
        viewModel.gatewayAddress = "myhost.ts.net"
        viewModel.connect()

        XCTAssertEqual(mockGateway.connectURL?.absoluteString, "wss://myhost.ts.net:18789")
    }

    func testConnectWithFullURLUsesItDirectly() {
        viewModel.gatewayAddress = "wss://custom.host:9999"
        viewModel.connect()

        XCTAssertEqual(mockGateway.connectURL?.absoluteString, "wss://custom.host:9999")
    }

    func testConnectSetsConnectingState() {
        viewModel.gatewayAddress = "myhost.ts.net"
        viewModel.connect()

        XCTAssertTrue(viewModel.isConnecting)
    }

    // MARK: - Paired After Hello-Ok

    func testGatewayConnectSetsPairedState() async throws {
        viewModel.gatewayAddress = "myhost.ts.net"
        viewModel.connect()
        mockGateway.simulateConnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isPaired)
        XCTAssertFalse(viewModel.isConnecting)
    }

    // MARK: - Disconnect / Unpair

    func testUnpairClearsPairingAndDisconnects() throws {
        try pairingManager.storeToken("token")
        let vm = PairingViewModel(pairingManager: pairingManager, gateway: mockGateway)

        vm.unpair()

        XCTAssertFalse(vm.isPaired)
        XCTAssertTrue(mockGateway.disconnectCalled)
        XCTAssertFalse(pairingManager.isPaired)
    }

    // MARK: - Connection Status

    func testConnectionStatusShowsConnectedWhenGatewayConnected() async throws {
        viewModel.gatewayAddress = "myhost.ts.net"
        viewModel.connect()
        mockGateway.simulateConnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.connectionStatus, .connected)
    }

    func testConnectionStatusShowsDisconnectedInitially() {
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
    }
}

// MARK: - VoicePairingViewModel Tests

@MainActor
final class VoicePairingViewModelTests: XCTestCase {

    var mockKeychain: MockKeychainAccess!
    var pairingManager: NodePairingManager!
    var mockGateway: MockGatewayConnecting!
    var viewModel: VoicePairingViewModel!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainAccess()
        pairingManager = NodePairingManager(keychain: mockKeychain)
        mockGateway = MockGatewayConnecting()
        viewModel = VoicePairingViewModel(pairingManager: pairingManager, gateway: mockGateway)
    }

    // MARK: - Disconnect during pairing should NOT show red error

    func testDisconnectWhileConnectingDoesNotShowError() async throws {
        // Simulate: user taps "Request Pairing", gateway disconnects before error callback
        viewModel.status = .connecting
        mockGateway.simulateDisconnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        // Should NOT be .failed — disconnect during connecting is expected for NOT_PAIRED flow
        if case .failed = viewModel.status {
            XCTFail("Disconnect while connecting should not show red error state, got: \(viewModel.status)")
        }
    }

    func testDisconnectWhileConnectingKeepsConnectingState() async throws {
        viewModel.status = .connecting
        mockGateway.simulateDisconnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.status, .connecting)
    }

    func testPairingRequiredErrorSetsAwaitingApproval() async throws {
        viewModel.status = .connecting
        mockGateway.simulateError(.challengeFailed("pairing_required:req-123"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.status, .awaitingApproval)
        XCTAssertEqual(viewModel.approvalRequestId, "req-123")
    }

    func testDisconnectWhilePairedShowsError() async throws {
        viewModel.status = .paired
        mockGateway.simulateDisconnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.status, .failed("Disconnected from gateway"))
    }

    func testGenuineErrorShowsRedState() async throws {
        viewModel.status = .connecting
        mockGateway.simulateError(.challengeFailed("auth_failed"))

        try await Task.sleep(nanoseconds: 50_000_000)

        if case .failed = viewModel.status {
            // Good — genuine errors should show red
        } else {
            XCTFail("Genuine errors should show failed state, got: \(viewModel.status)")
        }
    }

    func testConnectSetsPairedState() async throws {
        viewModel.status = .connecting
        mockGateway.simulateConnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.status, .paired)
    }
}
