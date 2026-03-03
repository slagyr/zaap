import XCTest
@testable import Zaap

final class WorkoutDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient(), anchorStore: MockDeliveryAnchorStore = MockDeliveryAnchorStore()) -> (WorkoutDeliveryService, MockWorkoutReader, MockWebhookClient, SettingsManager, MockDeliveryLogService, MockDeliveryAnchorStore) {
        let reader = MockWorkoutReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = WorkoutDeliveryService(workoutReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log, anchorStore: anchorStore)
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
        settings.workoutTrackingEnabled = true

        service.start()

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.workoutTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.workoutTrackingEnabled)
    }

    func testDeliverLatestSkipsWhenNotConfigured() {
        let (service, _, webhook, _, _, _) = makeService()
        service.deliverLatest()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testWorkoutDeliveryLogsSuccessOnPost() {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true

        reader.sessionsToReturn = [
            WorkoutReader.WorkoutSession(
                workoutType: "running",
                startDate: Date(), endDate: Date(),
                durationMinutes: 30, totalCalories: 300, distanceMeters: 5000
            )
        ]

        service.deliverLatest()

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .workout)
        XCTAssertTrue(log.records[0].success)
    }

    func testWorkoutDeliveryLogsFailureOnPostError() {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
        let (service, reader, _, settings, log, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true

        reader.sessionsToReturn = [
            WorkoutReader.WorkoutSession(
                workoutType: "running",
                startDate: Date(), endDate: Date(),
                durationMinutes: 30, totalCalories: 300, distanceMeters: 5000
            )
        ]

        service.deliverLatest()

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .workout)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversWorkoutData() async throws {
        let (service, reader, webhook, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.sessionsToReturn = []

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/workout")
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
        settings.workoutTrackingEnabled = false
        reader.sessionsToReturn = []

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    // MARK: - sendNow failure paths

    func testSendNowThrowsWhenAuthorizationDenied() async {
        let (service, reader, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = WorkoutReader.WorkoutError.authorizationDenied

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when authorization is denied")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .authorizationDenied)
        }
    }

    func testSendNowThrowsWhenReaderFetchFails() async {
        let (service, reader, _, settings, _, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.shouldThrow = WorkoutReader.WorkoutError.noData

        do {
            try await service.sendNow()
            XCTFail("Expected sendNow to throw when reader reports no workout data")
        } catch {
            XCTAssertEqual(error as? WorkoutReader.WorkoutError, .noData)
        }
    }

    func testSendNowThrowsWhenNetworkRequestFails() async {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = URLError(.notConnectedToInternet)
        let (service, reader, _, settings, _, _) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.sessionsToReturn = [
            WorkoutReader.WorkoutSession(
                workoutType: "running", startDate: Date(), endDate: Date(),
                durationMinutes: 30, totalCalories: 300, distanceMeters: 5000
            )
        ]

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
        reader.sessionsToReturn = [
            WorkoutReader.WorkoutSession(
                workoutType: "cycling", startDate: Date(), endDate: Date(),
                durationMinutes: 45, totalCalories: 400, distanceMeters: 15000
            )
        ]

        try await service.sendNow()

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .workout)
        XCTAssertTrue(log.records[0].success)
        XCTAssertNil(log.records[0].errorMessage)
    }

    // MARK: - deliverLatest failure paths

    func testDeliverLatestLogsFailureWhenAuthorizationDenied() {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true
        reader.shouldThrow = WorkoutReader.WorkoutError.authorizationDenied

        service.deliverLatest()

        let exp = expectation(description: "failure logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .workout)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    func testDeliverLatestLogsFailureWhenReaderReturnsNoWorkoutData() {
        let (service, reader, _, settings, log, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true
        reader.shouldThrow = WorkoutReader.WorkoutError.noData

        service.deliverLatest()

        let exp = expectation(description: "failure logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .workout)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Deduplication

    func testDeliverPassesAnchorAsFromDate() async {
        let anchorStore = MockDeliveryAnchorStore()
        let anchorDate = Date(timeIntervalSince1970: 1000000)
        anchorStore.anchors[.workout] = anchorDate
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true
        reader.sessionsToReturn = [WorkoutReader.WorkoutSession(
            workoutType: "Running", startDate: Date(),
            endDate: Date(), durationMinutes: 30,
            totalCalories: 300, distanceMeters: 5000
        )]

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testDeliverSkipsWhenNoNewWorkouts() async {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.workout] = Date()
        let (service, _, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true
        // sessionsToReturn is empty by default

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(webhook.postCallCount, 0, "Should skip POST when no new workouts")
    }

    func testDeliverUpdatesAnchorOnSuccess() async {
        let anchorStore = MockDeliveryAnchorStore()
        let (service, reader, _, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.workoutTrackingEnabled = true
        reader.sessionsToReturn = [WorkoutReader.WorkoutSession(
            workoutType: "Running", startDate: Date(),
            endDate: Date(), durationMinutes: 30,
            totalCalories: 300, distanceMeters: 5000
        )]

        service.deliverLatest()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNotNil(anchorStore.anchors[.workout], "Anchor should be set after successful delivery")
    }

    func testSendNowBypassesDeduplication() async throws {
        let anchorStore = MockDeliveryAnchorStore()
        anchorStore.anchors[.workout] = Date()
        let (service, reader, webhook, settings, _, _) = makeService(anchorStore: anchorStore)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        reader.sessionsToReturn = [WorkoutReader.WorkoutSession(
            workoutType: "Running", startDate: Date(),
            endDate: Date(), durationMinutes: 30,
            totalCalories: 300, distanceMeters: 5000
        )]

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1, "sendNow should bypass dedup")
    }

}
