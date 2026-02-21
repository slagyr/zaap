import XCTest
import Network
@testable import Zaap

// MARK: - Mock NWBrowser Wrapper

final class MockBrowserWrapper: GatewayBrowsing {
    var isSearching = false
    var onResultsChanged: (([DiscoveredGateway]) -> Void)?
    var simulatedResults: [DiscoveredGateway] = []

    func startBrowsing(onResultsChanged: @escaping ([DiscoveredGateway]) -> Void) {
        isSearching = true
        self.onResultsChanged = onResultsChanged
    }

    func stopBrowsing() {
        isSearching = false
        onResultsChanged = nil
    }

    func simulateDiscovery(_ gateways: [DiscoveredGateway]) {
        simulatedResults = gateways
        onResultsChanged?(gateways)
    }
}

// MARK: - Tests

final class GatewayBrowserTests: XCTestCase {

    // MARK: - DiscoveredGateway Model

    func testDiscoveredGatewayEquality() {
        let a = DiscoveredGateway(name: "MyMac", hostname: "mymac.local", port: 4444)
        let b = DiscoveredGateway(name: "MyMac", hostname: "mymac.local", port: 4444)
        XCTAssertEqual(a, b)
    }

    func testDiscoveredGatewayDisplayName() {
        let gw = DiscoveredGateway(name: "Zane's Mac", hostname: "zanes-mac.local", port: 4444)
        XCTAssertEqual(gw.displayName, "Zane's Mac")
    }

    func testDiscoveredGatewayDisplayNameFallsBackToHostname() {
        let gw = DiscoveredGateway(name: "", hostname: "zanes-mac.local", port: 4444)
        XCTAssertEqual(gw.displayName, "zanes-mac.local")
    }

    func testDiscoveredGatewayHostnameValue() {
        let gw = DiscoveredGateway(name: "Test", hostname: "myhost.local", port: 4444)
        XCTAssertEqual(gw.hostnameWithPort, "myhost.local:4444")
    }

    func testDiscoveredGatewayDefaultPort() {
        let gw = DiscoveredGateway(name: "Test", hostname: "myhost.local", port: 443)
        XCTAssertEqual(gw.hostnameWithPort, "myhost.local")
    }

    // MARK: - GatewayBrowserViewModel

    func testInitialStateIsEmpty() {
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock)
        XCTAssertTrue(vm.discoveredGateways.isEmpty)
        XCTAssertFalse(vm.isSearching)
    }

    func testStartSearchBeginsBrowsing() {
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock)
        vm.startSearching()
        XCTAssertTrue(vm.isSearching)
        XCTAssertTrue(mock.isSearching)
    }

    func testStopSearchStopsBrowsing() {
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock)
        vm.startSearching()
        vm.stopSearching()
        XCTAssertFalse(vm.isSearching)
        XCTAssertFalse(mock.isSearching)
    }

    func testDiscoveredGatewaysUpdateFromBrowser() {
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock)
        vm.startSearching()

        let gateways = [
            DiscoveredGateway(name: "Gateway1", hostname: "gw1.local", port: 4444),
            DiscoveredGateway(name: "Gateway2", hostname: "gw2.local", port: 4444),
        ]
        mock.simulateDiscovery(gateways)

        XCTAssertEqual(vm.discoveredGateways.count, 2)
        XCTAssertEqual(vm.discoveredGateways[0].name, "Gateway1")
        XCTAssertEqual(vm.discoveredGateways[1].name, "Gateway2")
    }

    func testSelectGatewayUpdatesSettings() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock, settings: settings)

        let gw = DiscoveredGateway(name: "MyGateway", hostname: "mygateway.local", port: 4444)
        vm.selectGateway(gw)

        XCTAssertEqual(settings.webhookURL, "mygateway.local:4444")
    }

    func testSelectGatewayDefaultPortOmitsPort() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock, settings: settings)

        let gw = DiscoveredGateway(name: "MyGateway", hostname: "mygateway.local", port: 443)
        vm.selectGateway(gw)

        XCTAssertEqual(settings.webhookURL, "mygateway.local")
    }

    func testHasDiscoveredGateways() {
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock)
        XCTAssertFalse(vm.hasDiscoveredGateways)

        vm.startSearching()
        mock.simulateDiscovery([DiscoveredGateway(name: "GW", hostname: "gw.local", port: 4444)])
        XCTAssertTrue(vm.hasDiscoveredGateways)
    }

    func testEmptyResultsClearsGateways() {
        let mock = MockBrowserWrapper()
        let vm = GatewayBrowserViewModel(browser: mock)
        vm.startSearching()

        mock.simulateDiscovery([DiscoveredGateway(name: "GW", hostname: "gw.local", port: 4444)])
        XCTAssertEqual(vm.discoveredGateways.count, 1)

        mock.simulateDiscovery([])
        XCTAssertTrue(vm.discoveredGateways.isEmpty)
    }
}
