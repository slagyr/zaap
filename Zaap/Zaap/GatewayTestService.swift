import Foundation

/// Tests the gateway WebSocket connection by attempting a ping.
final class GatewayTestService {

    struct TestResult {
        let success: Bool
        let errorMessage: String?
    }

    private let settings: SettingsManager

    init(settings: SettingsManager = .shared) {
        self.settings = settings
    }

    /// Attempts to connect to the gateway WebSocket and reports success/failure.
    func testConnection() async -> TestResult {
        guard let url = settings.voiceWebSocketURL else {
            return TestResult(success: false, errorMessage: "Gateway URL not configured")
        }

        var request = URLRequest(url: url)
        let token = settings.gatewayToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                wsTask.sendPing { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
            wsTask.cancel(with: .goingAway, reason: nil)
            return TestResult(success: true, errorMessage: nil)
        } catch {
            wsTask.cancel(with: .goingAway, reason: nil)
            return TestResult(success: false, errorMessage: error.localizedDescription)
        }
    }
}
