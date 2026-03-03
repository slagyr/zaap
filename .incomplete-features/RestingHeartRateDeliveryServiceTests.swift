import XCTest
@testable import Zaap

final class RestingHeartRateDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient(), anchorStore: MockDeliveryAnchorStore = MockDeliveryAnchorStore()) -> (RestingHeartRateDeliveryService, MockRestingHeartRateReader, MockWebhookClient, SettingsManager, MockDeliveryLogService, MockDeliveryAnchorStore) {
        let reader = MockRestingHeartRateReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = RestingHeartRateDeliveryService(restingHRReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log, anchorStore: anchorStore)
        return (service, reader, webhook, settings, log, anchorStore)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _, _, _) = makeService()
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testStartDoesNotDeliverEagerly() {
        let (service, _, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testReaderPropertyReturnsInjectedReader() {
        let (service, _, _, _, _, _) = makeService()
        XCTAssertNotNil(service.reader)
    }

    func testDeliverDailySummaryPostsToRestingHeartRatePath() async {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true

        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/resting-heart-rate")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _, _, _) = makeService()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.restingHeartRateTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.restingHeartRateTrackingEnabled)
    }

    func testDeliveryLogsSuccessOnPost() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true

        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .restingHeartRate)
        XCTAssertTrue(log.records[0].success)
    }

    func testDeliveryLogsFailureOnPostError() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true

        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .restingHeartRate)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversRestingHRData() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/resting-heart-rate")
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, reader, _, _, _, _) = makeService()
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SendNowError)
        }
    }

    func testSendNowWorksWhenTrackingDisabled() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = false
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testSendNowLogsSuccess() async throws {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        try await service.sendNow()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .restingHeartRate)
        XCTAssertTrue(log.records[0].success)
    }

    // MARK: - Deduplication

    func testDeliverSkipsWhenAlreadyDeliveredToday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.restingHeartRate] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 0, "Should skip when already delivered today")
    }

    func testDeliverProceedsWhenAnchorIsYesterday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.restingHeartRate] = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testDeliverUpdatesAnchorOnSuccess() async {
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertNotNil(anchorStore.anchors[.restingHeartRate])
    }

    func testDeliverDoesNotUpdateAnchorOnFailure() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1)
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook, anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        await service.deliverDailySummary()

        XCTAssertNil(anchorStore.anchors[.restingHeartRate])
    }

    func testSendNowBypassesDeduplication() async throws {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.restingHeartRate] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = RestingHeartRateReader.DailyRestingHRSummary(
            date: "2026-03-03", restingBPM: 58, sampleCount: 1,
            samples: [RestingHeartRateReader.RestingHRSample(bpm: 58, timestamp: Date())]
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1, "sendNow should bypass dedup")
    }

    // MARK: - Deliver failure paths

    func testDeliverDailySummaryLogsFailureWhenNoData() async {
        let (service, _, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.restingHeartRateTrackingEnabled = true

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .restingHeartRate)
        XCTAssertFalse(log.records[0].success)
    }
}
