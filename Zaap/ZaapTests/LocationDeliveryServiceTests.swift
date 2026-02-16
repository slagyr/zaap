import XCTest
import CoreLocation
@testable import Zaap

final class LocationDeliveryServiceTests: XCTestCase {

    private func makeService(
        locationManager: MockLocationPublishing = MockLocationPublishing(),
        webhook: MockWebhookClient = MockWebhookClient(),
        settings: SettingsManager? = nil
    ) -> (LocationDeliveryService, MockLocationPublishing, MockWebhookClient, SettingsManager) {
        let s = settings ?? SettingsManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = LocationDeliveryService(locationManager: locationManager, webhookClient: webhook, settings: s)
        return (service, locationManager, webhook, s)
    }

    func testStartResumesMonitoringWhenEnabled() {
        let (service, locMgr, _, settings) = makeService()
        settings.webhookURL = "https://example.com"
        settings.authToken = "token"
        settings.locationTrackingEnabled = true

        service.start()

        XCTAssertEqual(locMgr.startMonitoringCallCount, 1)
    }

    func testStartDoesNotMonitorWhenDisabled() {
        let (service, locMgr, _, _) = makeService()
        service.start()
        XCTAssertEqual(locMgr.startMonitoringCallCount, 0)
    }

    func testSetTrackingEnabledStartsMonitoring() {
        let (service, locMgr, _, _) = makeService()
        service.setTracking(enabled: true)
        XCTAssertEqual(locMgr.startMonitoringCallCount, 1)
    }

    func testSetTrackingDisabledStopsMonitoring() {
        let (service, locMgr, _, _) = makeService()
        service.setTracking(enabled: false)
        XCTAssertEqual(locMgr.stopMonitoringCallCount, 1)
    }

    func testLocationUpdateDeliversPayloadWhenConfigured() {
        let (service, locMgr, webhook, settings) = makeService()
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
        XCTAssertNil(webhook.lastPath) // posts to root
    }

    func testLocationUpdateSkipsDeliveryWhenNotConfigured() {
        let (service, locMgr, webhook, _) = makeService()
        service.start()

        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locMgr.locationPublisher.send(location)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(webhook.postCallCount, 0)
    }
}
