import Foundation

/// Tests connectivity to the OpenClaw gateway WebSocket endpoint.
final class GatewayTestService {

    struct TestResult {
        let success: Bool
        let errorMessage: String?
    }

    private let settings: SettingsManager

    init(settings: SettingsManager = .shared) {
        self.settings = settings
    }

    /// Attempts a basic WebSocket connection to verify gateway reachability.
    func testConnection() async -> TestResult {
        guard let url = settings.voiceWebSocketURL else {
            return TestResult(success: false, errorMessage: "Gateway URL not configured")
        }

        return await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: url)
            task.resume()

            // We just need to see if the connection succeeds (challenge received)
            task.receive { result in
                task.cancel(with: .normalClosure, reason: nil)
                switch result {
                case .success:
                    continuation.resume(returning: TestResult(success: true, errorMessage: nil))
                case .failure(let error):
                    continuation.resume(returning: TestResult(success: false, errorMessage: error.localizedDescription))
                }
            }

            // Timeout after 10 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                task.cancel(with: .normalClosure, reason: nil)
            }
        }
    }
}
