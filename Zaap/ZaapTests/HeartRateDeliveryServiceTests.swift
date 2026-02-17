import XCTest
@testable import Zaap

final class HeartRateDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient()) -> (HeartRateDeliveryService, MockHeartRateReader, MockWebhookClient, SettingsManager, MockDeliveryLogService) {
        let reader = MockHeartRateReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = HeartRateDeliveryService(heartRateReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log)
        return (service, reader, webhook, settings, log)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _, _) = makeService()
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testDeliverDailySummaryPostsToHeartRatePath() async {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true

        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-15", minBPM: 55, maxBPM: 150, avgBPM: 72,
            restingBPM: 58, sampleCount: 10, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/heartrate")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _, _) = makeService()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.heartRateTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.heartRateTrackingEnabled)
    }

    func testHeartRateDeliveryLogsSuccessOnPost() async {
        let (service, reader, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true

        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-15", minBPM: 55, maxBPM: 150, avgBPM: 72,
            restingBPM: 58, sampleCount: 10, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .heartRate)
        XCTAssertTrue(log.records[0].success)
    }

    func testHeartRateDeliveryLogsFailureOnPostError() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = true

        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-15", minBPM: 55, maxBPM: 150, avgBPM: 72,
            restingBPM: 58, sampleCount: 10, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .heartRate)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversHeartRateData() async throws {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-16", minBPM: 55, maxBPM: 120, avgBPM: 72,
            restingBPM: 60, sampleCount: 10, samples: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/heart-rate")
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, reader, _, _, _) = makeService()
        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-16", minBPM: 55, maxBPM: 120, avgBPM: 72,
            restingBPM: 60, sampleCount: 10, samples: []
        )

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SendNowError)
        }
    }

    func testSendNowWorksWhenTrackingDisabled() async throws {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.heartRateTrackingEnabled = false
        reader.summaryToReturn = HeartRateReader.DailyHeartRateSummary(
            date: "2026-02-16", minBPM: 55, maxBPM: 120, avgBPM: 72,
            restingBPM: 60, sampleCount: 10, samples: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }
}
