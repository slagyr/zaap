import Foundation
import os

/// Subscribes to sleep data changes and POSTs summaries via WebhookClient.
/// Mirrors LocationDeliveryService's pattern — query on demand and deliver via background session.
final class SleepDeliveryService {

    static let shared = SleepDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "SleepDelivery")

    private let sleepReader: any SleepReading
    private let webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private let deliveryLog: any DeliveryLogging

    init(
        sleepReader: any SleepReading = SleepDataReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog()
    ) {
        self.sleepReader = sleepReader
        self.webhookClient = webhookClient
        self.settings = settings
        self.deliveryLog = deliveryLog
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

    /// Immediately fetch and POST sleep data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await sleepReader.requestAuthorization()
        let summary = try await sleepReader.fetchLastNightSummary()
        try await webhookClient.post(summary, to: "/sleep")
        logger.info("Send Now: Sleep summary delivered")
        deliveryLog.record(dataType: .sleep, timestamp: Date(), success: true, errorMessage: nil)
    }
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
                deliveryLog.record(dataType: .sleep, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Sleep delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .sleep, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
