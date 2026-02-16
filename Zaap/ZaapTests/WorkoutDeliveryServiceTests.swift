import XCTest
@testable import Zaap

final class WorkoutDeliveryServiceTests: XCTestCase {

    private func makeService(webhook: MockWebhookClient = MockWebhookClient()) -> (WorkoutDeliveryService, MockWorkoutReader, MockWebhookClient, SettingsManager, MockDeliveryLogService) {
        let reader = MockWorkoutReader()
        let log = MockDeliveryLogService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = WorkoutDeliveryService(workoutReader: reader, webhookClient: webhook, settings: settings, deliveryLog: log)
        return (service, reader, webhook, settings, log)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _, _) = makeService()
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testStartDeliversWhenEnabled() {
        let (service, reader, webhook, settings, _) = makeService()
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

        service.start()

        let exp = expectation(description: "delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/workouts")
    }

    func testSetTrackingUpdatesSettings() {
        let (service, _, _, settings, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.workoutTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.workoutTrackingEnabled)
    }

    func testDeliverLatestSkipsWhenNotConfigured() {
        let (service, _, webhook, _, _) = makeService()
        service.deliverLatest()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testWorkoutDeliveryLogsSuccessOnPost() {
        let (service, reader, _, settings, log) = makeService()
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
        let (service, reader, _, settings, log) = makeService(webhook: webhook)
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
}
