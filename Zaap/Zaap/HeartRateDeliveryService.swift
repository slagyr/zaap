import Foundation
import os

/// Reads heart rate data from HeartRateReader and POSTs summaries via WebhookClient.
/// Follows the same pattern as LocationDeliveryService.
final class HeartRateDeliveryService {

    static let shared = HeartRateDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "HeartRateDelivery")

    private let heartRateReader: any HeartRateReading
    private let webhookClient: any WebhookPosting
    private let settings: SettingsManager

    init(
        heartRateReader: any HeartRateReading = HeartRateReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared
    ) {
        self.heartRateReader = heartRateReader
        self.webhookClient = webhookClient
        self.settings = settings
    }

    // MARK: - Public

    /// The heart rate reader used by this service (for UI binding).
    var reader: any HeartRateReading { heartRateReader }

    /// Start the heart rate delivery service.
    /// Requests HealthKit authorization and delivers an initial summary if enabled.
    func start() {
        guard settings.heartRateTrackingEnabled && settings.isConfigured else {
            logger.info("Heart rate delivery not started — not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await heartRateReader.requestAuthorization()
                await deliverDailySummary()
                logger.info("Heart rate delivery started")
            } catch {
                logger.error("Heart rate delivery start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Enable or disable heart rate tracking. Updates settings and triggers delivery if enabled.
    func setTracking(enabled: Bool) {
        settings.heartRateTrackingEnabled = enabled
        if enabled {
            start()
        }
    }

    /// Fetch and deliver the daily heart rate summary.
    func deliverDailySummary() async {
        guard settings.isConfigured && settings.heartRateTrackingEnabled else {
            logger.info("Skipping HR delivery — not configured or tracking disabled")
            return
        }

        do {
            let summary = try await heartRateReader.fetchDailySummary()
            try await webhookClient.post(summary, to: "/heart-rate")
            logger.info("Heart rate summary delivered: \(summary.sampleCount) samples, avg=\(summary.avgBPM)")
        } catch {
            logger.error("Heart rate delivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
