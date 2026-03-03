import XCTest
@testable import Zaap

final class RespiratoryRateDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient(), anchorStore: MockDeliveryAnchorStore = MockDeliveryAnchorStore()) -> (RespiratoryRateDeliveryService, MockRespiratoryRateReader, MockWebhookClient, SettingsManager, MockDeliveryLogService, MockDeliveryAnchorStore) {
        let reader = MockRespiratoryRateReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = RespiratoryRateDeliveryService(respiratoryRateReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log, anchorStore: anchorStore)
        return (service, reader, webhook, settings, log, anchorStore)
    }

    private func makeSummary() -> RespiratoryRateReader.DailyRespiratoryRateSummary {
        RespiratoryRateReader.DailyRespiratoryRateSummary(
            date: "2026-03-03", minRate: 12.0, maxRate: 20.0, avgRate: 15.5,
            sampleCount: 8, samples: []
        )
    }

    // MARK: - Start

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _, _, _) = makeService()
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testStartDoesNotDeliverEagerly() {
        let (service, _, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testReaderPropertyReturnsInjectedReader() {
        let (service, _, _, _, _, _) = makeService()
        XCTAssertNotNil(service.reader)
    }

    // MARK: - Deliver Daily Summary

    func testDeliverDailySummaryPostsToRespiratoryRatePath() async {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/respiratory-rate")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _, _, _) = makeService()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.respiratoryRateTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.respiratoryRateTrackingEnabled)
    }

    func testDeliveryLogsSuccessOnPost() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .respiratoryRate)
        XCTAssertTrue(log.records[0].success)
    }

    func testDeliveryLogsFailureOnPostError() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .respiratoryRate)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversRespiratoryRateData() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = makeSummary()
        try await service.sendNow()
        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/respiratory-rate")
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, reader, _, _, _, _) = makeService()
        reader.summaryToReturn = makeSummary()
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
        settings.respiratoryRateTrackingEnabled = false
        reader.summaryToReturn = makeSummary()
        try await service.sendNow()
        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testSendNowThrowsWhenAuthorizationDenied() async {
        let (service, reader, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = RespiratoryRateReader.RespiratoryRateError.authorizationDenied
        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? RespiratoryRateReader.RespiratoryRateError, .authorizationDenied)
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
            XCTAssertEqual(error as? RespiratoryRateReader.RespiratoryRateError, .noData)
        }
    }

    func testSendNowThrowsWhenNetworkFails() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = URLError(.notConnectedToInternet)
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = makeSummary()
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
        reader.summaryToReturn = makeSummary()
        try await service.sendNow()
        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .respiratoryRate)
        XCTAssertTrue(log.records[0].success)
    }

    // MARK: - Deduplication

    func testDeliverSkipsWhenAlreadyDeliveredToday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.respiratoryRate] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0, "Should skip when already delivered today")
    }

    func testDeliverProceedsWhenAnchorIsYesterday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.respiratoryRate] = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testDeliverUpdatesAnchorOnSuccess() async {
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertNotNil(anchorStore.anchors[.respiratoryRate])
    }

    func testDeliverDoesNotUpdateAnchorOnFailure() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1)
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook, anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.summaryToReturn = makeSummary()
        await service.deliverDailySummary()
        XCTAssertNil(anchorStore.anchors[.respiratoryRate])
    }

    func testSendNowBypassesDeduplication() async throws {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.respiratoryRate] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = makeSummary()
        try await service.sendNow()
        XCTAssertEqual(webhook.postCallCount, 1, "sendNow should bypass dedup")
    }

    // MARK: - Deliver failure paths

    func testDeliverDailySummaryLogsFailureWhenNoData() async {
        let (service, _, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        await service.deliverDailySummary()
        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .respiratoryRate)
        XCTAssertFalse(log.records[0].success)
    }

    func testDeliverDailySummaryLogsFailureWhenAuthDenied() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.respiratoryRateTrackingEnabled = true
        reader.shouldThrow = RespiratoryRateReader.RespiratoryRateError.authorizationDenied
        await service.deliverDailySummary()
        XCTAssertEqual(log.records.count, 1)
        XCTAssertFalse(log.records[0].success)
    }
}
