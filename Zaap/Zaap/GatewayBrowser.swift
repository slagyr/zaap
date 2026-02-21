import Foundation
import Network

// MARK: - Model

struct DiscoveredGateway: Equatable, Identifiable {
    let name: String
    let hostname: String
    let port: Int

    var id: String { "\(hostname):\(port)" }

    var displayName: String {
        name.isEmpty ? hostname : name
    }

    /// Returns hostname with port, omitting port if it's 443 (default HTTPS).
    var hostnameWithPort: String {
        port == 443 ? hostname : "\(hostname):\(port)"
    }
}

// MARK: - Protocol for testability

protocol GatewayBrowsing {
    func startBrowsing(onResultsChanged: @escaping ([DiscoveredGateway]) -> Void)
    func stopBrowsing()
}

// MARK: - Real NWBrowser wrapper

final class NWGatewayBrowser: GatewayBrowsing {
    private var browser: NWBrowser?
    private var onResults: (([DiscoveredGateway]) -> Void)?

    func startBrowsing(onResultsChanged: @escaping ([DiscoveredGateway]) -> Void) {
        self.onResults = onResultsChanged

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_openclaw._tcp", domain: nil), using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let gateways = results.compactMap { result -> DiscoveredGateway? in
                guard case .service(let name, let type, let domain, _) = result.endpoint else {
                    return nil
                }
                // We get name from the service; hostname/port resolved later via NWConnection
                // For now, use the service name and construct hostname from name
                return DiscoveredGateway(
                    name: name,
                    hostname: "\(name).\(domain)",
                    port: 4444 // default; will be resolved on selection
                )
            }
            DispatchQueue.main.async {
                self?.onResults?(gateways)
            }
        }

        browser.stateUpdateHandler = { state in
            // Could log state changes for debugging
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        onResults = nil
    }
}

// MARK: - ViewModel

@Observable
final class GatewayBrowserViewModel {
    private(set) var discoveredGateways: [DiscoveredGateway] = []
    private(set) var isSearching = false

    private let browser: GatewayBrowsing
    private let settings: SettingsManager?

    init(browser: GatewayBrowsing = NWGatewayBrowser(), settings: SettingsManager? = nil) {
        self.browser = browser
        self.settings = settings
    }

    func startSearching() {
        isSearching = true
        browser.startBrowsing { [weak self] gateways in
            self?.discoveredGateways = gateways
        }
    }

    func stopSearching() {
        isSearching = false
        browser.stopBrowsing()
    }

    func selectGateway(_ gateway: DiscoveredGateway) {
        settings?.webhookURL = gateway.hostnameWithPort
    }

    var hasDiscoveredGateways: Bool {
        !discoveredGateways.isEmpty
    }
}
