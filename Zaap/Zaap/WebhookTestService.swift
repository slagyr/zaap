import Foundation

/// Sends a lightweight ping to the webhook endpoint to verify connectivity.
final class WebhookTestService {

    struct TestResult {
        let success: Bool
        let errorMessage: String?
    }

    private let webhookClient: WebhookPosting
    private let settings: SettingsManager

    init(webhookClient: WebhookPosting = WebhookClient.shared, settings: SettingsManager = .shared) {
        self.webhookClient = webhookClient
        self.settings = settings
    }

    /// Sends a test ping POST to the webhook URL.
    func testConnection() async -> TestResult {
        guard settings.isConfigured else {
            return TestResult(success: false, errorMessage: "Webhook URL or token not configured")
        }

        do {
            let ping = PingPayload(type: "ping", timestamp: Date())
            try await webhookClient.post(ping, to: "/ping")
            return TestResult(success: true, errorMessage: nil)
        } catch {
            return TestResult(success: false, errorMessage: error.localizedDescription)
        }
    }
}

private struct PingPayload: Encodable {
    let type: String
    let timestamp: Date
}
