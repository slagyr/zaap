import Foundation
import os

/// Reads respiratory rate data from RespiratoryRateReader and POSTs summaries via WebhookClient.
/// Follows the same pattern as SpO2DeliveryService.
final class RespiratoryRateDeliveryService {

    static let shared = RespiratoryRateDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "RespiratoryRateDelivery")

    private let respiratoryRateReader: any RespiratoryRateReading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private let anchorStore: any DeliveryAnchorStoring

    init(
        respiratoryRateReader: any RespiratoryRateReading = RespiratoryRateReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.respiratoryRateReader = respiratoryRateReader
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

    /// The respiratory rate reader used by this service (for UI binding).
    var reader: any RespiratoryRateReading { respiratoryRateReader }

    /// Start the respiratory rate delivery service.
    func start() {
        guard settings.respiratoryRateTrackingEnabled && settings.isConfigured else {
            logger.info("Respiratory rate delivery not started \u{2014} not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await respiratoryRateReader.requestAuthorization()
                await deliverDailySummary()
                logger.info("Respiratory rate delivery started")
            } catch {
                logger.error("Respiratory rate delivery start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Enable or disable respiratory rate tracking.
    func setTracking(enabled: Bool) {
        settings.respiratoryRateTrackingEnabled = enabled
        if enabled {
            start()
        }
    }

    /// Immediately fetch and POST respiratory rate data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await respiratoryRateReader.requestAuthorization()
        let summary = try await respiratoryRateReader.fetchDailySummary(for: Date())
        try await webhookClient.postForeground(summary, to: "/respiratory-rate")
        logger.info("Send Now: Respiratory rate summary delivered")
        deliveryLog.record(dataType: .respiratoryRate, timestamp: Date(), success: true, errorMessage: nil)
    }

    /// Fetch and deliver the daily respiratory rate summary.
    func deliverDailySummary() async {
        guard settings.isConfigured && settings.respiratoryRateTrackingEnabled else {
            logger.info("Skipping respiratory rate delivery \u{2014} not configured or tracking disabled")
            return
        }

        if let anchor = anchorStore.lastDelivered(for: .respiratoryRate),
           Calendar.current.isDateInToday(anchor) {
            logger.info("Skipping respiratory rate delivery \u{2014} already delivered today")
            return
        }

        do {
            let summary = try await respiratoryRateReader.fetchDailySummary(for: Date())
            try await webhookClient.post(summary, to: "/respiratory-rate")
            anchorStore.setLastDelivered(Date(), for: .respiratoryRate)
            logger.info("Respiratory rate summary delivered: \(summary.sampleCount) samples, avg=\(summary.avgRate)")
            deliveryLog.record(dataType: .respiratoryRate, timestamp: Date(), success: true, errorMessage: nil)
        } catch {
            logger.error("Respiratory rate delivery failed: \(error.localizedDescription, privacy: .public)")
            deliveryLog.record(dataType: .respiratoryRate, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
        }
    }
}
