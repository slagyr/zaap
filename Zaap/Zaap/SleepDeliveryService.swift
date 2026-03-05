import Foundation
import os

/// Subscribes to sleep data changes and POSTs summaries via WebhookClient.
final class SleepDeliveryService {

    static let shared = SleepDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "SleepDelivery")

    private let sleepReader: any SleepReading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private var anchorStore: any DeliveryAnchorStoring

    init(
        sleepReader: any SleepReading = SleepDataReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.sleepReader = sleepReader
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

    func start() {
        guard settings.sleepTrackingEnabled && settings.isConfigured else {
            logger.info("Sleep delivery not started \u{2014} disabled or not configured")
            return
        }
        deliverLatest()
    }

    func setTracking(enabled: Bool) {
        settings.sleepTrackingEnabled = enabled
        if enabled {
            deliverLatest()
        }
    }

    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await sleepReader.requestAuthorization()
        let summary = try await sleepReader.fetchLastNightSummary()
        try await webhookClient.postForeground(summary, to: "/sleep")
        logger.info("Send Now: Sleep summary delivered")
        deliveryLog.record(dataType: .sleep, timestamp: Date(), success: true, errorMessage: nil)
    }

    func deliverLatest() {
        guard settings.isConfigured && settings.sleepTrackingEnabled else {
            logger.info("Skipping sleep delivery \u{2014} not configured or tracking disabled")
            return
        }

        if let anchor = anchorStore.lastDelivered(for: .sleep),
           Calendar.current.isDateInToday(anchor) {
            logger.info("Skipping sleep delivery \u{2014} already delivered today")
            return
        }

        Task {
            do {
                try await sleepReader.requestAuthorization()
                let summary = try await sleepReader.fetchLastNightSummary()
                try await webhookClient.post(summary, to: "/sleep")
                anchorStore.setLastDelivered(Date(), for: .sleep)
                logger.info("Sleep summary delivered for \(summary.date, privacy: .public)")
                deliveryLog.record(dataType: .sleep, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Sleep delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .sleep, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
