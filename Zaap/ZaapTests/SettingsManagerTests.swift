import XCTest
@testable import Zaap

final class SettingsManagerTests: XCTestCase {

    private func makeSettings() -> SettingsManager {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return SettingsManager(defaults: defaults)
    }

    // MARK: - Defaults

    func testWebhookURLDefaultsToEmpty() {
        let settings = makeSettings()
        XCTAssertEqual(settings.webhookURL, "")
    }

    func testAuthTokenDefaultsToEmpty() {
        let settings = makeSettings()
        XCTAssertEqual(settings.authToken, "")
    }

    func testTrackingFlagsDefaultToFalse() {
        let settings = makeSettings()
        XCTAssertFalse(settings.locationTrackingEnabled)
        XCTAssertFalse(settings.sleepTrackingEnabled)
        XCTAssertFalse(settings.workoutTrackingEnabled)
        XCTAssertFalse(settings.activityTrackingEnabled)
        XCTAssertFalse(settings.heartRateTrackingEnabled)
    }

    // MARK: - Persistence

    func testWebhookURLPersistsToUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        settings.webhookURL = "https://example.com/hook"
        XCTAssertEqual(defaults.string(forKey: "settings.webhookURL"), "https://example.com/hook")
    }

    func testAuthTokenPersistsToUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        settings.authToken = "secret123"
        XCTAssertEqual(defaults.string(forKey: "settings.authToken"), "secret123")
    }

    func testTrackingFlagPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsManager(defaults: defaults)
        settings.locationTrackingEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "settings.locationTrackingEnabled"))
    }

    func testLoadsPersistedValuesOnInit() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("https://hook.io", forKey: "settings.webhookURL")
        defaults.set("token", forKey: "settings.authToken")
        defaults.set(true, forKey: "settings.sleepTrackingEnabled")

        let settings = SettingsManager(defaults: defaults)
        XCTAssertEqual(settings.webhookURL, "https://hook.io")
        XCTAssertEqual(settings.authToken, "token")
        XCTAssertTrue(settings.sleepTrackingEnabled)
    }

    // MARK: - Computed Properties

    func testWebhookURLValueReturnsNilForEmptyString() {
        let settings = makeSettings()
        XCTAssertNil(settings.webhookURLValue)
    }

    func testWebhookURLValueReturnsURLForValidString() {
        let settings = makeSettings()
        settings.webhookURL = "https://example.com"
        XCTAssertEqual(settings.webhookURLValue?.absoluteString, "https://example.com")
    }

    func testIsConfiguredReturnsFalseWhenURLEmpty() {
        let settings = makeSettings()
        settings.authToken = "token"
        XCTAssertFalse(settings.isConfigured)
    }

    func testIsConfiguredReturnsFalseWhenTokenEmpty() {
        let settings = makeSettings()
        settings.webhookURL = "https://example.com"
        XCTAssertFalse(settings.isConfigured)
    }

    func testIsConfiguredReturnsTrueWhenBothSet() {
        let settings = makeSettings()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        XCTAssertTrue(settings.isConfigured)
    }
}
