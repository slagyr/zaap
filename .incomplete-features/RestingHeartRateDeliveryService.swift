import Foundation
import os

/// Reads resting heart rate data from RestingHeartRateReader and POSTs summaries via WebhookClient.
/// Follows the same pattern as HRVDeliveryService.
final class RestingHeartRateDeliveryService {

    static let shared = RestingHeartRateDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "RestingHRDelivery")

    private let restingHRReader: any RestingHeartRateReading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private let anchorStore: any DeliveryAnchorStoring

    init(
        restingHRReader: any RestingHeartRateReading = RestingHeartRateReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.restingHRReader = restingHRReader
        self.webhookClient = webhookClient
        self.settings = settings
        self.deliveryLog = deliveryLog
        self.anchorStore = anchorStore
    }

    func configure(deliveryLog: any DeliveryLogging) {
        self.deliveryLog = deliveryLog
    }

    func configure(webhookClient: any WebhookPosting) {
        self.webhookClient = webhookClient
    }

    // MARK: - Public

    /// The resting HR reader used by this service (for UI binding).
    var reader: any RestingHeartRateReading { restingHRReader }

    /// Start the resting heart rate delivery service.
    func start() {
        guard settings.restingHeartRateTrackingEnabled && settings.isConfigured else {
            logger.info("Resting HR delivery not started \u{2014} not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await restingHRReader.requestAuthorization()
                await deliverDailySummary()
                logger.info("Resting HR delivery started")
            } catch {
                logger.error("Resting HR delivery start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Enable or disable resting heart rate tracking.
    func setTracking(enabled: Bool) {
        settings.restingHeartRateTrackingEnabled = enabled
        if enabled {
            start()
        }
    }

    /// Immediately fetch and POST resting HR data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await restingHRReader.requestAuthorization()
        let summary = try await restingHRReader.fetchDailySummary(for: Date())
        try await webhookClient.postForeground(summary, to: "/resting-heart-rate")
        logger.info("Send Now: Resting HR summary delivered")
        deliveryLog.record(dataType: .restingHeartRate, timestamp: Date(), success: true, errorMessage: nil)
    }

    /// Fetch and deliver the daily resting heart rate summary.
    func deliverDailySummary() async {
        guard settings.isConfigured && settings.restingHeartRateTrackingEnabled else {
            logger.info("Skipping resting HR delivery \u{2014} not configured or tracking disabled")
            return
        }

        if let anchor = anchorStore.lastDelivered(for: .restingHeartRate),
           Calendar.current.isDateInToday(anchor) {
            logger.info("Skipping resting HR delivery \u{2014} already delivered today")
            return
        }

        do {
            let summary = try await restingHRReader.fetchDailySummary(for: Date())
            try await webhookClient.post(summary, to: "/resting-heart-rate")
            anchorStore.setLastDelivered(Date(), for: .restingHeartRate)
            logger.info("Resting HR summary delivered: \(summary.restingBPM) BPM")
            deliveryLog.record(dataType: .restingHeartRate, timestamp: Date(), success: true, errorMessage: nil)
        } catch {
            logger.error("Resting HR delivery failed: \(error.localizedDescription, privacy: .public)")
            deliveryLog.record(dataType: .restingHeartRate, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
        }
    }
}
