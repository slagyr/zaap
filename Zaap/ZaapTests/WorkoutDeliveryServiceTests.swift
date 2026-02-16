import XCTest
@testable import Zaap

final class WorkoutDeliveryServiceTests: XCTestCase {

    private func makeService() -> (WorkoutDeliveryService, MockWorkoutReader, MockWebhookClient, SettingsManager) {
        let reader = MockWorkoutReader()
        let webhook = MockWebhookClient()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = WorkoutDeliveryService(workoutReader: reader, webhookClient: webhook, settings: settings)
        return (service, reader, webhook, settings)
    }

    func testStartDoesNothingWhenDisabled() {
        let (service, _, webhook, _) = makeService()
        service.start()
        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testStartDeliversWhenEnabled() {
        let (service, reader, webhook, settings) = makeService()
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
        let (service, _, _, settings) = makeService()
        service.setTracking(enabled: true)
        XCTAssertTrue(settings.workoutTrackingEnabled)
        service.setTracking(enabled: false)
        XCTAssertFalse(settings.workoutTrackingEnabled)
    }

    func testDeliverLatestSkipsWhenNotConfigured() {
        let (service, _, webhook, _) = makeService()
        service.deliverLatest()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(webhook.postCallCount, 0)
    }
}
