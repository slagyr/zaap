import Foundation
import os

/// Reads daily activity data from HealthKit via ActivityReader and POSTs it via WebhookClient.
/// Mirrors SleepDeliveryService's pattern — query on demand and deliver via background session.
final class ActivityDeliveryService {

    static let shared = ActivityDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "ActivityDelivery")

    private let activityReader: any ActivityReading
    private let webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private let deliveryLog: any DeliveryLogging

    init(
        activityReader: any ActivityReading = ActivityReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog()
    ) {
        self.activityReader = activityReader
        self.webhookClient = webhookClient
        self.settings = settings
        self.deliveryLog = deliveryLog
    }

    // MARK: - Public

    /// Start the service. If activity tracking was previously enabled, deliver the latest summary.
    /// Call once at app launch.
    func start() {
        guard settings.activityTrackingEnabled && settings.isConfigured else {
            logger.info("Activity delivery not started — disabled or not configured")
            return
        }
        deliverLatest()
    }

    /// Enable or disable activity tracking. Updates settings and triggers delivery if enabled.
    func setTracking(enabled: Bool) {
        settings.activityTrackingEnabled = enabled
        if enabled {
            deliverLatest()
        }
    }


    /// Immediately fetch and POST activity data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await activityReader.requestAuthorization()
        let summary = try await activityReader.fetchTodaySummary()
        try await webhookClient.post(summary, to: "/activity")
        logger.info("Send Now: Activity data delivered")
        deliveryLog.record(dataType: .activity, timestamp: Date(), success: true, errorMessage: nil)
    }
    /// Fetch the latest activity summary and POST it to the webhook.
    func deliverLatest() {
        guard settings.isConfigured && settings.activityTrackingEnabled else {
            logger.info("Skipping activity delivery — not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await activityReader.requestAuthorization()
                let summary = try await activityReader.fetchTodaySummary()
                try await webhookClient.post(summary, to: "/activity")
                logger.info("Activity delivered: \(summary.steps) steps, \(String(format: "%.0f", summary.distanceMeters))m")
                deliveryLog.record(dataType: .activity, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Activity delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .activity, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
