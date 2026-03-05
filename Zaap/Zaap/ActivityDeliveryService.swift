import Foundation
import os

/// Reads daily activity data from HealthKit via ActivityReader and POSTs it via WebhookClient.
final class ActivityDeliveryService {

    static let shared = ActivityDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "ActivityDelivery")

    private let activityReader: any ActivityReading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private var anchorStore: any DeliveryAnchorStoring

    init(
        activityReader: any ActivityReading = ActivityReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.activityReader = activityReader
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
        guard settings.activityTrackingEnabled && settings.isConfigured else {
            logger.info("Activity delivery not started \u{2014} disabled or not configured")
            return
        }
        deliverLatest()
    }

    func setTracking(enabled: Bool) {
        settings.activityTrackingEnabled = enabled
        if enabled {
            deliverLatest()
        }
    }

    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await activityReader.requestAuthorization()
        let summary = try await activityReader.fetchTodaySummary()
        try await webhookClient.postForeground(summary, to: "/activity")
        logger.info("Send Now: Activity data delivered")
        deliveryLog.record(dataType: .activity, timestamp: Date(), success: true, errorMessage: nil)
    }

    func deliverLatest() {
        guard settings.isConfigured && settings.activityTrackingEnabled else {
            logger.info("Skipping activity delivery \u{2014} not configured or tracking disabled")
            return
        }

        if let anchor = anchorStore.lastDelivered(for: .activity),
           Calendar.current.isDateInToday(anchor) {
            logger.info("Skipping activity delivery \u{2014} already delivered today")
            return
        }

        Task {
            do {
                try await activityReader.requestAuthorization()
                let summary = try await activityReader.fetchTodaySummary()
                try await webhookClient.post(summary, to: "/activity")
                anchorStore.setLastDelivered(Date(), for: .activity)
                logger.info("Activity delivered: \(summary.steps) steps, \(String(format: "%.0f", summary.distanceMeters))m")
                deliveryLog.record(dataType: .activity, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Activity delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .activity, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
