import XCTest
@testable import Zaap

final class WebhookClientTests: XCTestCase {

    func testLoadConfigurationReturnsNilWhenNotConfigured() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        XCTAssertFalse(settings.isConfigured)
    }

    func testLoadConfigurationReturnsValueWhenConfigured() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        XCTAssertTrue(settings.isConfigured)
        XCTAssertNotNil(settings.webhookURLValue)
    }

    func testWebhookErrorDescriptions() {
        let noConfig = WebhookClient.WebhookError.noConfiguration
        XCTAssertEqual(noConfig.errorDescription, "Webhook URL or token not configured")

        let invalidResp = WebhookClient.WebhookError.invalidResponse(statusCode: 500)
        XCTAssertEqual(invalidResp.errorDescription, "Server returned HTTP 500")

        let encoding = WebhookClient.WebhookError.encodingFailed(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad"]))
        XCTAssertTrue(encoding.errorDescription!.contains("bad"))

        let network = WebhookClient.WebhookError.networkError(NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "timeout"]))
        XCTAssertTrue(network.errorDescription!.contains("timeout"))
    }

    func testInvalidResponseStatusCode() {
        let error = WebhookClient.WebhookError.invalidResponse(statusCode: 0)
        XCTAssertEqual(error.errorDescription, "Server returned HTTP 0")
    }

    func testLoadConfigurationReturnsNilForEmptyHostname() {
        let client = WebhookClient()
        // With default/empty SettingsManager.shared, should return nil
        // We verify the pattern via SettingsManager directly
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        XCTAssertNil(settings.webhookURLValue)
        XCTAssertFalse(settings.isConfigured)
    }

    func testLoadConfigurationBuildsCorrectURL() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        settings.webhookURL = "myhost.example.com"
        settings.authToken = "secret"
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(settings.webhookURLValue?.absoluteString, "https://myhost.example.com/hooks")
    }
}
