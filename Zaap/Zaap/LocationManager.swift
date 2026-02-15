import Foundation
import CoreLocation
import Combine

/// Manages significant location change monitoring via CLLocationManager.
/// Publishes location updates as a Combine publisher and via async stream.
@Observable
final class LocationManager: NSObject {

    // MARK: - Published State

    /// Most recent location, or nil if not yet received.
    var currentLocation: CLLocation?

    /// Authorization status for location services.
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether significant location change monitoring is actively running.
    var isMonitoring: Bool = false

    /// Last error encountered, if any.
    var lastError: Error?

    // MARK: - Combine

    /// Publishes every location update received from significant change monitoring.
    let locationPublisher = PassthroughSubject<CLLocation, Never>()

    // MARK: - Private

    private let manager = CLLocationManager()

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Public API

    /// Requests "always" authorization (required for background significant location changes).
    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Starts significant location change monitoring.
    /// Requests authorization first if not yet determined.
    func startMonitoring() {
        if authorizationStatus == .notDetermined {
            requestAuthorization()
        }

        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            lastError = LocationError.significantChangeUnavailable
            return
        }

        manager.startMonitoringSignificantLocationChanges()
        isMonitoring = true
    }

    /// Stops significant location change monitoring.
    func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        isMonitoring = false
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        locationPublisher.send(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - Errors

enum LocationError: LocalizedError {
    case significantChangeUnavailable

    var errorDescription: String? {
        switch self {
        case .significantChangeUnavailable:
            return "Significant location change monitoring is not available on this device."
        }
    }
}
