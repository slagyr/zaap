import XCTest
@testable import Zaap

final class HeartRateDeliveryServiceTests: XCTestCase {

    private func makeService() -> (HeartRateDeliveryService, MockHeartRateReader, MockWebhookClient, SettingsManager) {
        let reader = MockHeartRateReader()
        let webhook = MockWebhookClient()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = HeartRateDeliveryService(heartRateReader: reader, webhookClient: webhook, settings: settings)
        return (service, reader, webhook, settings)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _) = makeService()
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testDeliverDailySummaryPostsToHeartRatePath() async {
        let (service, reader, webhook, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true

        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-15", minBPM: 55, maxBPM: 150, avgBPM: 72,
            restingBPM: 58, sampleCount: 10, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/heart-rate")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _) = makeService()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.heartRateTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.heartRateTrackingEnabled)
    }
}
