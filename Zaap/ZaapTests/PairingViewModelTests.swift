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

// MARK: - Dual-Role Pairing Tests

@MainActor
final class DualRolePairingTests: XCTestCase {

    var mockKeychain: MockKeychainAccess!
    var pairingManager: NodePairingManager!
    var mockFactory: MockGatewayFactory!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainAccess()
        pairingManager = NodePairingManager(keychain: mockKeychain)
        mockFactory = MockGatewayFactory()
    }

    private func createViewModel() -> VoicePairingViewModel {
        VoicePairingViewModel(pairingManager: pairingManager, gatewayFactory: mockFactory)
    }

    // MARK: - Role Detection

    func testNeedsNodePairingWhenNoNodeToken() {
        let vm = createViewModel()
        XCTAssertEqual(vm.currentRole, "node")
    }

    func testNeedsOperatorPairingWhenNodeTokenExists() throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        let vm = createViewModel()
        XCTAssertEqual(vm.currentRole, "operator")
    }

    func testAlreadyPairedWhenBothTokensExist() throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        try pairingManager.storeToken("operator-token", forRole: "operator")
        let vm = createViewModel()
        XCTAssertEqual(vm.status, .paired)
    }

    // MARK: - Sequential Pairing: Node then Operator

    func testRequestPairingCreatesNodeGatewayFirst() {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        XCTAssertEqual(mockFactory.createdGateways.count, 1)
        XCTAssertEqual(mockFactory.createdGateways.first?.createdForRole, .node)
    }

    func testNodePairedAdvancesToOperatorRole() async throws {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        // Simulate node pairing succeeds
        let nodeGateway = mockFactory.createdGateways[0]
        // Simulate hello-ok storing a token
        try pairingManager.storeToken("node-token", forRole: "node")
        nodeGateway.simulateConnect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.currentRole, "operator")
        XCTAssertEqual(vm.status, .connecting)
        // Should have created a second gateway for operator
        XCTAssertEqual(mockFactory.createdGateways.count, 2)
        XCTAssertEqual(mockFactory.createdGateways[1].createdForRole, .operator)
    }

    func testOperatorPairedSetsFinalPairedStatus() async throws {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        // Pair node
        let nodeGateway = mockFactory.createdGateways[0]
        try pairingManager.storeToken("node-token", forRole: "node")
        nodeGateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Pair operator
        let operatorGateway = mockFactory.createdGateways[1]
        try pairingManager.storeToken("operator-token", forRole: "operator")
        operatorGateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.status, .paired)
    }

    func testSkipsNodePairingWhenNodeAlreadyPaired() async throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        // Should go straight to operator
        XCTAssertEqual(mockFactory.createdGateways.count, 1)
        XCTAssertEqual(mockFactory.createdGateways.first?.createdForRole, .operator)
        XCTAssertEqual(vm.currentRole, "operator")
    }

    // MARK: - Awaiting Approval Per Role

    func testAwaitingApprovalShowsForNodeRole() async throws {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        let nodeGateway = mockFactory.createdGateways[0]
        nodeGateway.simulateError(.challengeFailed("pairing_required:req-node-1"))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.status, .awaitingApproval)
        XCTAssertEqual(vm.currentRole, "node")
        XCTAssertEqual(vm.approvalRequestId, "req-node-1")
    }

    func testAwaitingApprovalShowsForOperatorRole() async throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        let operatorGateway = mockFactory.createdGateways[0]
        operatorGateway.simulateError(.challengeFailed("pairing_required:req-op-1"))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.status, .awaitingApproval)
        XCTAssertEqual(vm.currentRole, "operator")
        XCTAssertEqual(vm.approvalRequestId, "req-op-1")
    }

    // MARK: - Disconnect node gateway before starting operator

    func testDisconnectsNodeGatewayBeforeStartingOperator() async throws {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        let nodeGateway = mockFactory.createdGateways[0]
        try pairingManager.storeToken("node-token", forRole: "node")
        nodeGateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(nodeGateway.disconnectCalled)
    }

    // MARK: - Step Progress Indicator

    func testCurrentStepIsOneWhenPairingNode() {
        let vm = createViewModel()
        XCTAssertEqual(vm.currentStep, 1)
        XCTAssertEqual(vm.totalSteps, 2)
    }

    func testCurrentStepIsTwoWhenPairingOperator() throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        let vm = createViewModel()
        XCTAssertEqual(vm.currentStep, 2)
        XCTAssertEqual(vm.totalSteps, 2)
    }

    func testStepAdvancesFromOneToTwoAfterNodePaired() async throws {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        let nodeGateway = mockFactory.createdGateways[0]
        try pairingManager.storeToken("node-token", forRole: "node")
        nodeGateway.simulateConnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.currentStep, 2)
    }

    // MARK: - Role Descriptions

    func testRoleDescriptionForNode() {
        let vm = createViewModel()
        XCTAssertEqual(vm.roleDescription, "Voice sends audio and receives spoken responses.")
    }

    func testRoleDescriptionForOperator() throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        let vm = createViewModel()
        XCTAssertEqual(vm.roleDescription, "Operator sends commands and manages your session.")
    }

    // MARK: - Friendly Status Messages

    func testConnectingStatusMessageForNode() {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()
        XCTAssertEqual(vm.statusMessage, "Setting up voice channel...")
    }

    func testConnectingStatusMessageForOperator() throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()
        XCTAssertEqual(vm.statusMessage, "Setting up operator channel...")
    }

    func testAwaitingApprovalStatusMessage() async throws {
        let vm = createViewModel()
        SettingsManager.shared.webhookURL = "test.host"
        vm.requestPairing()

        let nodeGateway = mockFactory.createdGateways[0]
        nodeGateway.simulateError(.challengeFailed("pairing_required:req-node-1"))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.statusMessage, "Waiting for approval on gateway...")
    }

    func testPairedStatusMessage() throws {
        try pairingManager.storeToken("node-token", forRole: "node")
        try pairingManager.storeToken("operator-token", forRole: "operator")
        let vm = createViewModel()
        XCTAssertEqual(vm.statusMessage, "All set! Device is paired.")
    }

    func testIdleStatusMessageIsEmpty() {
        let vm = createViewModel()
        XCTAssertEqual(vm.statusMessage, "")
    }
}
