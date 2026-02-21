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
