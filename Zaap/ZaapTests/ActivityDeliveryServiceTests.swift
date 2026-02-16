import XCTest
@testable import Zaap

final class ActivityDeliveryServiceTests: XCTestCase {

    private func makeService() -> (ActivityDeliveryService, MockActivityReader, MockWebhookClient, SettingsManager) {
        let reader = MockActivityReader()
        let webhook = MockWebhookClient()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = ActivityDeliveryService(activityReader: reader, webhookClient: webhook, settings: settings)
        return (service, reader, webhook, settings)
    }

    func testDeliverCurrentActivityPostsToActivityPath() async {
        let (service, reader, webhook, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true

        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-15", steps: 8000,
            distanceMeters: 6400, activeEnergyKcal: 350,
            timestamp: Date()
        )

        await service.deliverCurrentActivity()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/activity")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _) = makeService()
        await service.deliverCurrentActivity()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.activityTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.activityTrackingEnabled)
    }

    func testStartDeliversWhenEnabled() {
        let (service, reader, webhook, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true

        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-15", steps: 5000,
            distanceMeters: 4000, activeEnergyKcal: 200,
            timestamp: Date()
        )

        service.start()

        let exp = expectation(description: "delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 1)
    }
}
