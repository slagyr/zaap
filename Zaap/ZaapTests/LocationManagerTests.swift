import XCTest
import CoreLocation
@testable import Zaap

@MainActor
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

    func testDidUpdateLocationsIgnoresEmptyArray() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [])
        XCTAssertNil(manager.currentLocation)
    }

    func testAuthorizationChangeUpdatesStatus() {
        let manager = LocationManager()
        let clManager = CLLocationManager()
        manager.locationManagerDidChangeAuthorization(clManager)
        // Just verifies it doesn't crash and updates the status
        XCTAssertEqual(manager.authorizationStatus, clManager.authorizationStatus)
    }

    func testStopMonitoringSetsIsMonitoringFalse() {
        let manager = LocationManager()
        manager.stopMonitoring()
        XCTAssertFalse(manager.isMonitoring)
    }

    func testLastErrorInitiallyNil() {
        let manager = LocationManager()
        XCTAssertNil(manager.lastError)
    }
}
