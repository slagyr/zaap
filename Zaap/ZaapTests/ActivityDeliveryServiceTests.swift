import XCTest
@testable import Zaap

final class ActivityDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient(), anchorStore: MockDeliveryAnchorStore = MockDeliveryAnchorStore()) -> (ActivityDeliveryService, MockActivityReader, MockWebhookClient, SettingsManager, MockDeliveryLogService, MockDeliveryAnchorStore) {
        let reader = MockActivityReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = ActivityDeliveryService(activityReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log, anchorStore: anchorStore)
        return (service, reader, webhook, settings, log, anchorStore)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _, _, _) = makeService()
        service.start()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testDeliverLatestPostsToActivityPath() {
        let (service, reader, webhook, settings, _, _) = makeService()
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
        let (service, _, webhook, _, _, _) = makeService()
        service.deliverLatest()

        let exp = expectation(description: "no delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.activityTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.activityTrackingEnabled)
    }

    func testStartDoesNotDeliverEagerly() {
        let (service, _, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true

        service.start()

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testActivityDeliveryLogsSuccessOnPost() {
        let (service, reader, _, settings, log, _) = makeService()
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
        let (service, reader, _, settings, log, _) = makeService(webhook: webhook)
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

    // MARK: - Send Now

    func testSendNowDeliversActivityData() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-16", steps: 1000, distanceMeters: 800,
            activeEnergyKcal: 200, timestamp: Date()
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/activity")
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, _, _, _, _, _) = makeService()

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
        settings.activityTrackingEnabled = false
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-16", steps: 1000, distanceMeters: 800,
            activeEnergyKcal: 200, timestamp: Date()
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    // MARK: - sendNow failure paths

    func testSendNowThrowsWhenAuthorizationDenied() async {
        let (service, reader, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = ActivityReader.ActivityError.authorizationDenied

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when authorization is denied")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .authorizationDenied)
        }
    }

    func testSendNowThrowsWhenNoActivityDataAvailable() async {
        let (service, _, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        // summaryToReturn is nil by default → fetchTodaySummary throws noData after auth succeeds

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when no activity data is available")
        } catch {
            XCTAssertEqual(error as? ActivityReader.ActivityError, .noData)
        }
    }

    func testSendNowThrowsWhenNetworkRequestFails() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = URLError(.notConnectedToInternet)
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-19", steps: 5000, distanceMeters: 4000,
            activeEnergyKcal: 250, timestamp: Date()
        )

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when network request fails")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testSendNowLogsSuccessOnDelivery() async throws {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-02-19", steps: 5000, distanceMeters: 4000,
            activeEnergyKcal: 250, timestamp: Date()
        )

        try await service.sendNow()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .activity)
        XCTAssertTrue(log.records[0].success)
        XCTAssertNil(log.records[0].errorMessage)
    }

    // MARK: - deliverLatest failure paths

    func testDeliverLatestLogsFailureWhenNoActivityDataAvailable() {
        let (service, _, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true
        // summaryToReturn is nil → fetchTodaySummary throws noData

        service.deliverLatest()

        let exp = expectation(description: "failure logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .activity)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    func testDeliverLatestLogsFailureWhenAuthorizationDenied() {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true
        reader.shouldThrow = ActivityReader.ActivityError.authorizationDenied

        service.deliverLatest()

        let exp = expectation(description: "failure logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .activity)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Deduplication

    func testDeliverSkipsWhenAlreadyDeliveredToday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.activity] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-03-03", steps: 5000,
            distanceMeters: 3500.0, activeEnergyKcal: 250.0,
            timestamp: Date()
        )

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(webhook.postCallCount, 0, "Should skip delivery when already delivered today")
    }

    func testDeliverProceedsWhenAnchorIsYesterday() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.activity] = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-03-03", steps: 5000,
            distanceMeters: 3500.0, activeEnergyKcal: 250.0,
            timestamp: Date()
        )

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(webhook.postCallCount, 1, "Should deliver when anchor is from yesterday")
    }

    func testDeliverUpdatesAnchorOnSuccess() async {
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-03-03", steps: 5000,
            distanceMeters: 3500.0, activeEnergyKcal: 250.0,
            timestamp: Date()
        )

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNotNil(anchorStore.anchors[.activity], "Anchor should be set after successful delivery")
    }

    func testDeliverDoesNotUpdateAnchorOnFailure() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1)
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook, anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.activityTrackingEnabled = true
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-03-03", steps: 5000,
            distanceMeters: 3500.0, activeEnergyKcal: 250.0,
            timestamp: Date()
        )

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNil(anchorStore.anchors[.activity], "Anchor should not be set on failed delivery")
    }

    func testSendNowBypassesDeduplication() async throws {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.activity] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = ActivityReader.ActivitySummary(
            date: "2026-03-03", steps: 5000,
            distanceMeters: 3500.0, activeEnergyKcal: 250.0,
            timestamp: Date()
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1, "sendNow should bypass dedup")
    }

}
