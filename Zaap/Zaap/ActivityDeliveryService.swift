import Foundation
import os

/// Reads daily activity data from HealthKit via ActivityReader and POSTs it via WebhookClient.
final class ActivityDeliveryService {

    static let shared = ActivityDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "ActivityDelivery")

    private let activityReader: ActivityReader
    private let webhookClient: WebhookClient
    private let settings: SettingsManager

    init(
        activityReader: ActivityReader = .shared,
        webhookClient: WebhookClient = .shared,
        settings: SettingsManager = .shared
    ) {
        self.activityReader = activityReader
        self.webhookClient = webhookClient
        self.settings = settings
    }

    // MARK: - Public

    /// The activity reader used by this service (for UI binding / authorization).
    var reader: ActivityReader { activityReader }

    /// Enable or disable activity tracking. Updates settings and triggers an initial read if enabled.
    func setTracking(enabled: Bool) {
        settings.activityTrackingEnabled = enabled
        if enabled {
            Task { await deliverCurrentActivity() }
        }
    }

    /// Fetch current activity data and deliver via webhook.
    func deliverCurrentActivity() async {
        guard settings.isConfigured && settings.activityTrackingEnabled else {
            logger.info("Skipping activity delivery — not configured or tracking disabled")
            return
        }

        do {
            try await activityReader.requestAuthorization()
            let summary = try await activityReader.fetchTodaySummary()
            try await webhookClient.post(summary, to: "/activity")
            logger.info("Activity delivered: \(summary.steps) steps")
        } catch {
            logger.error("Activity delivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Call on app launch to deliver activity if tracking is enabled.
    func start() {
        if settings.activityTrackingEnabled && settings.isConfigured {
            Task { await deliverCurrentActivity() }
            logger.info("Activity delivery started on launch")
        }
    }
}
