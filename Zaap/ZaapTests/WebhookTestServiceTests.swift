import XCTest
@testable import Zaap

final class WebhookTestServiceTests: XCTestCase {

    func testTestConnectionSucceedsWithValidConfig() async {
        let mockClient = MockWebhookClient()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.webhookURL = "https://example.com/hooks"
        settings.authToken = "test-token"

        let service = WebhookTestService(webhookClient: mockClient, settings: settings)
        let result = await service.testConnection()

        XCTAssertTrue(result.success)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(mockClient.postCallCount, 1)
        XCTAssertEqual(mockClient.lastPath, "/ping")
    }

    func testTestConnectionFailsWhenNotConfigured() async {
        let mockClient = MockWebhookClient()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)

        let service = WebhookTestService(webhookClient: mockClient, settings: settings)
        let result = await service.testConnection()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorMessage, "Webhook URL or token not configured")
        XCTAssertEqual(mockClient.postCallCount, 0)
    }

    func testTestConnectionFailsOnNetworkError() async {
        let mockClient = MockWebhookClient()
        mockClient.shouldThrow = WebhookClient.WebhookError.networkError(
            NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
        )
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.webhookURL = "https://example.com/hooks"
        settings.authToken = "test-token"

        let service = WebhookTestService(webhookClient: mockClient, settings: settings)
        let result = await service.testConnection()

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorMessage)
    }

    func testTestConnectionFailsOnServerError() async {
        let mockClient = MockWebhookClient()
        mockClient.shouldThrow = WebhookClient.WebhookError.invalidResponse(statusCode: 500)
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.webhookURL = "https://example.com/hooks"
        settings.authToken = "test-token"

        let service = WebhookTestService(webhookClient: mockClient, settings: settings)
        let result = await service.testConnection()

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorMessage)
    }

    func testTestConnectionFailsWithInvalidURL() async {
        let mockClient = MockWebhookClient()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.webhookURL = ""
        settings.authToken = "test-token"

        let service = WebhookTestService(webhookClient: mockClient, settings: settings)
        let result = await service.testConnection()

        XCTAssertFalse(result.success)
        XCTAssertEqual(mockClient.postCallCount, 0)
    }
}
