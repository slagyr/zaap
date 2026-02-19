import Foundation
import CoreLocation
import Combine
import os

/// Subscribes to LocationManager's location updates and POSTs them via WebhookClient.
/// Designed to work in the background — uses Combine to react to location events
/// and the background URLSession in WebhookClient for delivery.
final class LocationDeliveryService {

    static let shared = LocationDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "LocationDelivery")
    private var cancellables = Set<AnyCancellable>()

    private let locationManager: any LocationPublishing
    private let webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private let deliveryLog: any DeliveryLogging

    init(
        locationManager: any LocationPublishing = LocationManager(),
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog()
    ) {
        self.locationManager = locationManager
        self.webhookClient = webhookClient
        self.settings = settings
        self.deliveryLog = deliveryLog
    }

    // MARK: - Public

    /// The location manager used by this service (for UI binding).
    var location: any LocationPublishing { locationManager }

    /// Start observing location updates and delivering them via webhook.
    /// Call once at app launch.
    func start() {
        locationManager.locationPublisher
            .sink { [weak self] location in
                self?.deliver(location)
            }
            .store(in: &cancellables)

        // If location tracking was previously enabled, resume monitoring.
        if settings.locationTrackingEnabled && settings.isConfigured {
            locationManager.startMonitoring()
            logger.info("Resumed location monitoring on launch")
        }
    }

    /// Enable or disable location tracking. Updates settings and starts/stops monitoring.
    func setTracking(enabled: Bool) {
        settings.locationTrackingEnabled = enabled
        if enabled {
            locationManager.startMonitoring()
        } else {
            locationManager.stopMonitoring()
        }
    }


    /// Immediately read the current location and POST it to the webhook.
    /// Does not require tracking to be enabled, but does require configuration.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        guard let location = locationManager.currentLocation else {
            throw SendNowError.noData("No current location available.")
        }
        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp
        )
        try await webhookClient.postForeground(payload, to: "/location")
        logger.info("Send Now: Location delivered")
        deliveryLog.record(dataType: .location, timestamp: Date(), success: true, errorMessage: nil)
    }
    // MARK: - Private

    private func deliver(_ location: CLLocation) {
        guard settings.isConfigured && settings.locationTrackingEnabled else {
            logger.info("Skipping delivery — not configured or tracking disabled")
            return
        }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp
        )

        Task {
            do {
                try await webhookClient.post(payload, to: "/location")
                logger.info("Location delivered: \(payload.latitude), \(payload.longitude)")
                deliveryLog.record(dataType: .location, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Location delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .location, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}

// MARK: - Payload

struct LocationPayload: Encodable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speed: Double
    let course: Double
    let timestamp: Date
}
