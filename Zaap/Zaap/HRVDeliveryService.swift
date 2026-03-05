import Foundation
import os

/// Reads HRV data from HRVReader and POSTs summaries via WebhookClient.
/// Follows the same pattern as HeartRateDeliveryService.
final class HRVDeliveryService {

    static let shared = HRVDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "HRVDelivery")

    private let hrvReader: any HRVReading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private var anchorStore: any DeliveryAnchorStoring

    init(
        hrvReader: any HRVReading = HRVReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.hrvReader = hrvReader
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

    func configure(anchorStore: any DeliveryAnchorStoring) {
        self.anchorStore = anchorStore
    }

    // MARK: - Public

    /// The HRV reader used by this service (for UI binding).
    var reader: any HRVReading { hrvReader }

    /// Start the HRV delivery service.
    func start() {
        guard settings.hrvTrackingEnabled && settings.isConfigured else {
            logger.info("HRV delivery not started \u{2014} not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await hrvReader.requestAuthorization()
                await deliverDailySummary()
                logger.info("HRV delivery started")
            } catch {
                logger.error("HRV delivery start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Enable or disable HRV tracking.
    func setTracking(enabled: Bool) {
        settings.hrvTrackingEnabled = enabled
        if enabled {
            start()
        }
    }

    /// Immediately fetch and POST HRV data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await hrvReader.requestAuthorization()
        let summary = try await hrvReader.fetchDailySummary(for: Date())
        try await webhookClient.postForeground(summary, to: "/hrv")
        logger.info("Send Now: HRV summary delivered")
        deliveryLog.record(dataType: .hrv, timestamp: Date(), success: true, errorMessage: nil)
    }

    /// Fetch and deliver the daily HRV summary.
    func deliverDailySummary() async {
        guard settings.isConfigured && settings.hrvTrackingEnabled else {
            logger.info("Skipping HRV delivery \u{2014} not configured or tracking disabled")
            return
        }

        if let anchor = anchorStore.lastDelivered(for: .hrv),
           Calendar.current.isDateInToday(anchor) {
            logger.info("Skipping HRV delivery \u{2014} already delivered today")
            return
        }

        do {
            let summary = try await hrvReader.fetchDailySummary(for: Date())
            try await webhookClient.post(summary, to: "/hrv")
            anchorStore.setLastDelivered(Date(), for: .hrv)
            logger.info("HRV summary delivered: \(summary.sampleCount) samples, avg=\(summary.avgSDNN)")
            deliveryLog.record(dataType: .hrv, timestamp: Date(), success: true, errorMessage: nil)
        } catch {
            logger.error("HRV delivery failed: \(error.localizedDescription, privacy: .public)")
            deliveryLog.record(dataType: .hrv, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
        }
    }
}
