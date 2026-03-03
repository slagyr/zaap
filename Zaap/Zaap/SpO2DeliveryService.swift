import Foundation
import os

/// Reads SpO2 data from SpO2Reader and POSTs summaries via WebhookClient.
/// Follows the same pattern as HRVDeliveryService.
final class SpO2DeliveryService {

    static let shared = SpO2DeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "SpO2Delivery")

    private let spo2Reader: any SpO2Reading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private let anchorStore: any DeliveryAnchorStoring

    init(
        spo2Reader: any SpO2Reading = SpO2Reader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.spo2Reader = spo2Reader
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

    /// The SpO2 reader used by this service (for UI binding).
    var reader: any SpO2Reading { spo2Reader }

    /// Start the SpO2 delivery service.
    func start() {
        guard settings.spo2TrackingEnabled && settings.isConfigured else {
            logger.info("SpO2 delivery not started \u{2014} not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await spo2Reader.requestAuthorization()
                await deliverDailySummary()
                logger.info("SpO2 delivery started")
            } catch {
                logger.error("SpO2 delivery start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Enable or disable SpO2 tracking.
    func setTracking(enabled: Bool) {
        settings.spo2TrackingEnabled = enabled
        if enabled {
            start()
        }
    }

    /// Immediately fetch and POST SpO2 data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await spo2Reader.requestAuthorization()
        let summary = try await spo2Reader.fetchDailySummary(for: Date())
        try await webhookClient.postForeground(summary, to: "/spo2")
        logger.info("Send Now: SpO2 summary delivered")
        deliveryLog.record(dataType: .spo2, timestamp: Date(), success: true, errorMessage: nil)
    }

    /// Fetch and deliver the daily SpO2 summary.
    func deliverDailySummary() async {
        guard settings.isConfigured && settings.spo2TrackingEnabled else {
            logger.info("Skipping SpO2 delivery \u{2014} not configured or tracking disabled")
            return
        }

        if let anchor = anchorStore.lastDelivered(for: .spo2),
           Calendar.current.isDateInToday(anchor) {
            logger.info("Skipping SpO2 delivery \u{2014} already delivered today")
            return
        }

        do {
            let summary = try await spo2Reader.fetchDailySummary(for: Date())
            try await webhookClient.post(summary, to: "/spo2")
            anchorStore.setLastDelivered(Date(), for: .spo2)
            logger.info("SpO2 summary delivered: \(summary.sampleCount) samples, avg=\(summary.avgSpO2)")
            deliveryLog.record(dataType: .spo2, timestamp: Date(), success: true, errorMessage: nil)
        } catch {
            logger.error("SpO2 delivery failed: \(error.localizedDescription, privacy: .public)")
            deliveryLog.record(dataType: .spo2, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
        }
    }
}
