import XCTest
import CoreLocation
@testable import Zaap

final class LocationDeliveryServiceTests: XCTestCase {

    private func makeService(
        locationManager: MockLocationPublishing = MockLocationPublishing(),
        webhook: MockWebhookClient = MockWebhookClient(),
        settings: SettingsManager? = nil,
        deliveryLog: MockDeliveryLogService = MockDeliveryLogService()
    ) -> (LocationDeliveryService, MockLocationPublishing, MockWebhookClient, SettingsManager, MockDeliveryLogService) {
        let s = settings ?? SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = LocationDeliveryService(locationManager: locationManager, webhookClient: webhook, settings: s, deliveryLog: deliveryLog)
        return (service, locationManager, webhook, s, deliveryLog)
    }

    func testStartResumesMonitoringWhenEnabled() {
        let (service, locMgr, _, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.locationTrackingEnabled = true

        service.start()

        XCTAssertEqual(locMgr.startMonitoringCallCount, 1)
    }

    func testStartDoesNotMonitorWhenDisabled() {
        let (service, locMgr, _, _, _) = makeService()
        service.start()
        XCTAssertEqual(locMgr.startMonitoringCallCount, 0)
    }

    func testSetTrackingEnabledStartsMonitoring() {
        let (service, locMgr, _, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertEqual(locMgr.startMonitoringCallCount, 1)
    }

    func testSetTrackingDisabledStopsMonitoring() {
        let (service, locMgr, _, _, _) = makeService()
        service.setTracking(enabled: false)
        XCTAssertEqual(locMgr.stopMonitoringCallCount, 1)
    }

    func testLocationUpdateDeliversPayloadWhenConfigured() {
        let (service, locMgr, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.locationTrackingEnabled = true

        service.start()

        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locMgr.locationPublisher.send(location)

        // Give async Task time to complete
        let exp = expectation(description: "webhook called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(webhook.postCallCount, 1)
        XCTAssertEqual(webhook.lastPath, "/location")
    }

    func testLocationUpdateSkipsDeliveryWhenNotConfigured() {
        let (service, locMgr, webhook, _, _) = makeService()
        service.start()

        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locMgr.locationPublisher.send(location)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(webhook.postCallCount, 0)
    }

    func testLocationDeliveryLogsSuccessOnPost() {
        let (service, locMgr, _, settings, log) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.locationTrackingEnabled = true

        service.start()

        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locMgr.locationPublisher.send(location)

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .location)
        XCTAssertTrue(log.records[0].success)
        XCTAssertNil(log.records[0].errorMessage)
    }

    func testLocationDeliveryLogsFailureOnPostError() {
        let webhook = MockWebhookClient()
        webhook.shouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network down"])
        let (service, locMgr, _, settings, log) = makeService(webhook: webhook)
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.locationTrackingEnabled = true

        service.start()

        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locMgr.locationPublisher.send(location)

        let exp = expectation(description: "logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].dataType, .location)
        XCTAssertFalse(log.records[0].success)
        XCTAssertNotNil(log.records[0].errorMessage)
    }

    // MARK: - Send Now

    func testSendNowDeliversCurrentLocation() async throws {
        let (service, locMgr, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        locMgr.currentLocation = CLLocation(latitude: 33.45, longitude: -112.07)

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }

    func testSendNowThrowsWhenNotConfigured() async {
        let (service, locMgr, _, _, _) = makeService()
        locMgr.currentLocation = CLLocation(latitude: 33.45, longitude: -112.07)

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SendNowError)
        }
    }

    func testSendNowThrowsWhenNoCurrentLocation() async {
        let (service, _, _, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"

        do {
            try await service.sendNow()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SendNowError)
        }
    }

    func testSendNowWorksEvenWhenTrackingDisabled() async throws {
        let (service, locMgr, webhook, settings, _) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.locationTrackingEnabled = false
        locMgr.currentLocation = CLLocation(latitude: 33.45, longitude: -112.07)

        try await service.sendNow()

        XCTAssertEqual(webhook.postCallCount, 1)
    }
}
