import XCTest
@testable import Zaap

final class SpO2DeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient(), anchorStore: MockDeliveryAnchorStore = MockDeliveryAnchorStore()) -> (SpO2DeliveryService, MockSpO2Reader, MockWebhookClient, SettingsManager, MockDeliveryLogService, MockDeliveryAnchorStore) {
        let reader = MockSpO2Reader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = SpO2DeliveryService(spo2Reader: reader, webhookClient: webhook, settings: settings, deliveryLog: log, anchorStore: anchorStore)
        return (service, reader, webhook, settings, log, anchorStore)
    }

    private func makeSummary() -> SpO2Reader.DailySpO2Summary {
        SpO2Reader.DailySpO2Summary(
            date: "2026-03-03", minSpO2: 94, maxSpO2: 99, avgSpO2: 97,
            sampleCount: 5, samples: []
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
        settings.spo2TrackingEnabled = true

        service.start()

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testReaderPropertyReturnsInjectedReader() {
        let (service, _, _, _, _, _) = makeService()
        XCTAssertNotNil(service.reader)
    }

    // MARK: - Deliver Daily Summary

    func testDeliverDailySummaryPostsToSpO2Path() async {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/spo2")
    }

    func testDeliverSkipsWhenNotConfigured() async {
        let (service, _, webhook, _, _, _) = makeService()
        await service.deliverDailySummary()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.spo2TrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.spo2TrackingEnabled)
    }

    func testDeliveryLogsSuccessOnPost() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .spo2)
        XCTAssertTrue(log.records[0].success)
    }

    func testDeliveryLogsFailureOnPostError() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .spo2)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversSpO2Data() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = makeSummary()

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/spo2")
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
        settings.spo2TrackingEnabled = false
        reader.summaryToReturn = makeSummary()

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testSendNowThrowsWhenAuthorizationDenied() async {
        let (service, reader, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = SpO2Reader.SpO2Error.authorizationDenied

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SpO2Reader.SpO2Error, .authorizationDenied)
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
            XCTAssertEqual(error as? SpO2Reader.SpO2Error, .noData)
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
        XCTAssertEqual(log.records[0].dataType, .spo2)
        XCTAssertTrue(log.records[0].success)
    }

    // MARK: - Deduplication

    func testDeliverSkipsWhenAlreadyDeliveredToday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.spo2] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 0, "Should skip when already delivered today")
    }

    func testDeliverProceedsWhenAnchorIsYesterday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.spo2] = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testDeliverUpdatesAnchorOnSuccess() async {
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertNotNil(anchorStore.anchors[.spo2])
    }

    func testDeliverDoesNotUpdateAnchorOnFailure() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1)
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook, anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.summaryToReturn = makeSummary()

        await service.deliverDailySummary()

        XCTAssertNil(anchorStore.anchors[.spo2])
    }

    func testSendNowBypassesDeduplication() async throws {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.spo2] = Date()
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
        settings.spo2TrackingEnabled = true

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .spo2)
        XCTAssertFalse(log.records[0].success)
    }

    func testDeliverDailySummaryLogsFailureWhenAuthDenied() async {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.spo2TrackingEnabled = true
        reader.shouldThrow = SpO2Reader.SpO2Error.authorizationDenied

        await service.deliverDailySummary()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertFalse(log.records[0].success)
    }
}
