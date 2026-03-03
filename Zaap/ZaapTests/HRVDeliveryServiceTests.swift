import XCTest
@testable import Zaap

final class HRVDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient(), anchorStore: MockDeliveryAnchorStore = MockDeliveryAnchorStore()) -> (HRVDeliveryService, MockHRVReader, MockWebhookClient, SettingsManager, MockDeliveryLogService, MockDeliveryAnchorStore) {
        let reader = MockHRVReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = HRVDeliveryService(hrvReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log, anchorStore: anchorStore)
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
        settings.hrvTrackingEnabled = true

        service.start()

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testReaderPropertyReturnsInjectedReader() {
        let (service, _, _, _, _, _) = makeService()
        XCTAssertNotNil(service.reader)
    }

    func testDeliverDailySummaryPostsToHRVPath() async {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true

        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/hrv")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _, _, _) = makeService()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.hrvTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.hrvTrackingEnabled)
    }

    func testDeliveryLogsSuccessOnPost() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true

        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .hrv)
        XCTAssertTrue(log.records[0].success)
    }

    func testDeliveryLogsFailureOnPostError() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true

        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .hrv)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversHRVData() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/hrv")
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, reader, _, _, _, _) = makeService()
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
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
        settings.hrvTrackingEnabled = false
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testSendNowThrowsWhenAuthorizationDenied() async {
        let (service, reader, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = HRVReader.HRVError.authorizationDenied

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? HRVReader.HRVError, .authorizationDenied)
        }
    }

    func testSendNowThrowsWhenNoDataAvailable() async {
        let (service, _, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? HRVReader.HRVError, .noData)
        }
    }

    func testSendNowThrowsWhenNetworkFails() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = URLError(.notConnectedToInternet)
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testSendNowLogsSuccess() async throws {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        try await service.sendNow()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .hrv)
        XCTAssertTrue(log.records[0].success)
    }

    // MARK: - Deduplication

    func testDeliverSkipsWhenAlreadyDeliveredToday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.hrv] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 0, "Should skip when already delivered today")
    }

    func testDeliverProceedsWhenAnchorIsYesterday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.hrv] = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testDeliverUpdatesAnchorOnSuccess() async {
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertNotNil(anchorStore.anchors[.hrv])
    }

    func testDeliverDoesNotUpdateAnchorOnFailure() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1)
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook, anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        await service.deliverDailySummary()

        XCTAssertNil(anchorStore.anchors[.hrv])
    }

    func testSendNowBypassesDeduplication() async throws {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.hrv] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = HRVReader.DailyHRVSummary(
            date: "2026-03-03", minSDNN: 20, maxSDNN: 80, avgSDNN: 45,
            sampleCount: 5, samples: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1, "sendNow should bypass dedup")
    }

    // MARK: - Deliver failure paths

    func testDeliverDailySummaryLogsFailureWhenNoData() async {
        let (service, _, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .hrv)
        XCTAssertFalse(log.records[0].success)
    }

    func testDeliverDailySummaryLogsFailureWhenAuthDenied() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.hrvTrackingEnabled = true
        reader.shouldThrow = HRVReader.HRVError.authorizationDenied

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertFalse(log.records[0].success)
    }
}
