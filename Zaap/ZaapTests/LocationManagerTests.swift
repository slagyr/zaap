import XCTest
import CoreLocation
@testable import Zaap

final class LocationManagerTests: XCTestCase {

    func testInitialStateIsNotMonitoring() {
        let manager = LocationManager()
        XCTAssertFalse(manager.isMonitoring)
    }

    func testInitialLocationIsNil() {
        let manager = LocationManager()
        XCTAssertNil(manager.currentLocation)
    }

    func testLocationErrorDescription() {
        let error = LocationError.significantChangeUnavailable
        XCTAssertEqual(error.errorDescription, "Significant location change monitoring is not available on this device.")
    }

    func testLocationPublisherEmitsOnDelegateCallback() {
        let manager = LocationManager()
        let expectation = expectation(description: "location published")
        var receivedLocation: CLLocation?

        let cancellable = manager.locationPublisher.sink { location in
            receivedLocation = location
            expectation.fulfill()
        }

        // Simulate delegate callback
        let testLocation = CLLocation(latitude: 33.4484, longitude: -112.0740)
        manager.locationManager(CLLocationManager(), didUpdateLocations: [testLocation])

        waitForExpectations(timeout: 1)
        XCTAssertEqual(receivedLocation?.coordinate.latitude, 33.4484)
        XCTAssertEqual(manager.currentLocation?.coordinate.latitude, 33.4484)
        cancellable.cancel()
    }

    func testDelegateErrorSetsLastError() {
        let manager = LocationManager()
        let error = NSError(domain: "test", code: 42)
        manager.locationManager(CLLocationManager(), didFailWithError: error)
        XCTAssertNotNil(manager.lastError)
    }
}
