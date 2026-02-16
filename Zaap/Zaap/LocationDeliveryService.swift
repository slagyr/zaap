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

    init(
        locationManager: any LocationPublishing = LocationManager(),
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared
    ) {
        self.locationManager = locationManager
        self.webhookClient = webhookClient
        self.settings = settings
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
                try await webhookClient.post(payload)
                logger.info("Location delivered: \(payload.latitude), \(payload.longitude)")
            } catch {
                logger.error("Location delivery failed: \(error.localizedDescription, privacy: .public)")
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
