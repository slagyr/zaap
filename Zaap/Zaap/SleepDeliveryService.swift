import Foundation
import os

/// Subscribes to sleep data changes and POSTs summaries via WebhookClient.
/// Mirrors LocationDeliveryService's pattern — query on demand and deliver via background session.
final class SleepDeliveryService {

    static let shared = SleepDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "SleepDelivery")

    private let sleepReader: SleepDataReader
    private let webhookClient: WebhookClient
    private let settings: SettingsManager

    init(
        sleepReader: SleepDataReader = .shared,
        webhookClient: WebhookClient = .shared,
        settings: SettingsManager = .shared
    ) {
        self.sleepReader = sleepReader
        self.webhookClient = webhookClient
        self.settings = settings
    }

    // MARK: - Public

    /// Start the service. If sleep tracking was previously enabled, deliver the latest summary.
    /// Call once at app launch.
    func start() {
        guard settings.sleepTrackingEnabled && settings.isConfigured else {
            logger.info("Sleep delivery not started — disabled or not configured")
            return
        }
        deliverLatest()
    }

    /// Enable or disable sleep tracking. Updates settings and triggers delivery if enabled.
    func setTracking(enabled: Bool) {
        settings.sleepTrackingEnabled = enabled
        if enabled {
            deliverLatest()
        }
    }

    /// Fetch the latest sleep summary and POST it to the webhook.
    func deliverLatest() {
        guard settings.isConfigured && settings.sleepTrackingEnabled else {
            logger.info("Skipping sleep delivery — not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await sleepReader.requestAuthorization()
                let summary = try await sleepReader.fetchLastNightSummary()
                try await webhookClient.post(summary, to: "/sleep")
                logger.info("Sleep summary delivered for \(summary.date, privacy: .public)")
            } catch {
                logger.error("Sleep delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
