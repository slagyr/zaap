import XCTest
@testable import Zaap

final class ActivityDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient()) -> (ActivityDeliveryService, MockActivityReader, MockWebhookClient, SettingsManager, MockDeliveryLogService) {
        let reader = MockActivityReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = ActivityDeliveryService(activityReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log)
        return (service, reader, webhook, settings, log)
    }

    func testDeliverLatestPostsToActivityPath() {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true

        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-15", steps: 8000,
            distanceMeters: 6400, activeEnergyKcal: 350,
            timestamp: Date()
        )

        service.deliverLatest()

        let exp = expectation(description: "delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/activity")
    }

    func testDeliverSkipsWhenNotConfigured() {
        let (service, _, webhook, _, _) = makeService()
        service.deliverLatest()

        let exp = expectation(description: "no delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.activityTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.activityTrackingEnabled)
    }

    func testStartDeliversWhenEnabled() {
        let (service, reader, webhook, settings, _) = makeService()
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

    func testActivityDeliveryLogsSuccessOnPost() {
        let (service, reader, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true

        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-15", steps: 8000,
            distanceMeters: 6400, activeEnergyKcal: 350,
            timestamp: Date()
        )

        service.deliverLatest()

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .activity)
        XCTAssertTrue(log.records[0].success)
    }

    func testActivityDeliveryLogsFailureOnPostError() {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true

        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-15", steps: 8000,
            distanceMeters: 6400, activeEnergyKcal: 350,
            timestamp: Date()
        )

        service.deliverLatest()

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .activity)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }
}
