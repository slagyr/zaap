import XCTest
@testable import Zaap

final class SleepDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient()) -> (SleepDeliveryService, MockSleepReader, MockWebhookClient, SettingsManager, MockDeliveryLogService) {
        let reader = MockSleepReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = SleepDeliveryService(sleepReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log)
        return (service, reader, webhook, settings, log)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, reader, webhook, _, _) = makeService()
        service.start()
        XCTAssertFalse(reader.authorizationRequested)
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testStartDeliversWhenEnabled() {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.sleepTrackingEnabled = true

        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-15", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        service.start()

        let exp = expectation(description: "delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/sleep")
    }

    func testSetTrackingEnabledTriggersDelivery() {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"

        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-15", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 0, totalAsleepMinutes: 0,
            deepSleepMinutes: 0, remSleepMinutes: 0, coreSleepMinutes: 0,
            awakeMinutes: 0, sessions: []
        )

        service.setTracking(enabled: true)
        XCTAssertTrue(settings.sleepTrackingEnabled)

        let exp = expectation(description: "delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testSleepDeliveryLogsSuccessOnPost() {
        let (service, reader, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.sleepTrackingEnabled = true

        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-15", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        service.deliverLatest()

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .sleep)
        XCTAssertTrue(log.records[0].success)
    }

    func testSleepDeliveryLogsFailureOnPostError() {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.sleepTrackingEnabled = true

        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-15", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        service.deliverLatest()

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .sleep)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversSleepData() async throws {
        let (service, reader, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-15", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/sleep")
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, _, _, _, _) = makeService()

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
        settings.sleepTrackingEnabled = false
        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-15", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    // MARK: - sendNow failure paths

    func testSendNowThrowsWhenAuthorizationDenied() async {
        let (service, reader, _, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = SleepDataReader.SleepError.authorizationDenied

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when authorization is denied")
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .authorizationDenied)
        }
    }

    func testSendNowThrowsWhenNoSleepDataAvailable() async {
        let (service, _, _, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        // summaryToReturn is nil by default → fetchLastNightSummary throws noData after auth succeeds

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when no sleep data is available")
        } catch {
            XCTAssertEqual(error as? SleepDataReader.SleepError, .noData)
        }
    }

    func testSendNowThrowsWhenNetworkRequestFails() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = URLError(.notConnectedToInternet)
        let (service, reader, _, settings, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-19", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when network request fails")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testSendNowLogsSuccessOnDelivery() async throws {
        let (service, reader, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.summaryToReturn = SleepDataReader.SleepSummary(
            date: "2026-02-19", bedtime: nil, wakeTime: nil,
            totalInBedMinutes: 480, totalAsleepMinutes: 420,
            deepSleepMinutes: 90, remSleepMinutes: 120, coreSleepMinutes: 210,
            awakeMinutes: 30, sessions: []
        )

        try await service.sendNow()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .sleep)
        XCTAssertTrue(log.records[0].success)
        XCTAssertNil(log.records[0].errorMessage)
    }

    // MARK: - deliverLatest failure paths

    func testDeliverLatestLogsFailureWhenNoSleepDataAvailable() {
        let (service, _, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.sleepTrackingEnabled = true
        // summaryToReturn is nil → fetchLastNightSummary throws noData

        service.deliverLatest()

        let exp = expectation(description: "failure logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .sleep)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    func testDeliverLatestLogsFailureWhenAuthorizationDenied() {
        let (service, reader, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.sleepTrackingEnabled = true
        reader.shouldThrow = SleepDataReader.SleepError.authorizationDenied

        service.deliverLatest()

        let exp = expectation(description: "failure logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .sleep)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }
}
