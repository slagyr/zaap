import Foundation

/// Abstracts URLSession for testability.
protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// Tests connectivity to the OpenClaw gateway using the gateway bearer token.
/// Sends an HTTP GET to /health on the gateway hostname.
final class GatewayTestService {

    struct TestResult {
        let success: Bool
        let errorMessage: String?
    }

    private let session: URLSessionProtocol
    private let settings: SettingsManager

    init(session: URLSessionProtocol = URLSession.shared, settings: SettingsManager = .shared) {
        self.session = session
        self.settings = settings
    }

    func testConnection() async -> TestResult {
        let hostname = settings.hostname
        guard !hostname.isEmpty else {
            return TestResult(success: false, errorMessage: "Gateway hostname not configured")
        }
        guard !settings.gatewayToken.isEmpty else {
            return TestResult(success: false, errorMessage: "Gateway bearer token not configured")
        }

        let scheme = settings.isLocalHostname ? "http" : "https"
        guard let url = URL(string: "\(scheme)://\(hostname)/health") else {
            return TestResult(success: false, errorMessage: "Invalid gateway URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(settings.gatewayToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return TestResult(success: false, errorMessage: "Invalid response")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return TestResult(success: false, errorMessage: "Gateway returned HTTP \(httpResponse.statusCode)")
            }
            return TestResult(success: true, errorMessage: nil)
        } catch {
            return TestResult(success: false, errorMessage: error.localizedDescription)
        }
    }
}
