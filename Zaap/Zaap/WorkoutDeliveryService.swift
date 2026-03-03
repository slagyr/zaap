import Foundation
import os

/// Fetches recent workouts and POSTs them via WebhookClient.
final class WorkoutDeliveryService {

    static let shared = WorkoutDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "WorkoutDelivery")

    private let workoutReader: any WorkoutReading
    private var webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private var deliveryLog: any DeliveryLogging
    private let anchorStore: any DeliveryAnchorStoring

    init(
        workoutReader: any WorkoutReading = WorkoutReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog(),
        anchorStore: any DeliveryAnchorStoring = NullDeliveryAnchorStore()
    ) {
        self.workoutReader = workoutReader
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

    func start() {
        guard settings.workoutTrackingEnabled && settings.isConfigured else {
            logger.info("Workout delivery not started \u{2014} disabled or not configured")
            return
        }
        deliverLatest()
    }

    func setTracking(enabled: Bool) {
        settings.workoutTrackingEnabled = enabled
        if enabled {
            deliverLatest()
        }
    }

    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await workoutReader.requestAuthorization()
        let sessions = try await workoutReader.fetchRecentSessions(from: nil, to: nil)
        try await webhookClient.postForeground(sessions, to: "/workout")
        logger.info("Send Now: Workout data delivered")
        deliveryLog.record(dataType: .workout, timestamp: Date(), success: true, errorMessage: nil)
    }

    func deliverLatest() {
        guard settings.isConfigured && settings.workoutTrackingEnabled else {
            logger.info("Skipping workout delivery \u{2014} not configured or tracking disabled")
            return
        }

        let anchor = anchorStore.lastDelivered(for: .workout)

        Task {
            do {
                try await workoutReader.requestAuthorization()
                let sessions = try await workoutReader.fetchRecentSessions(from: anchor, to: nil)
                guard !sessions.isEmpty else {
                    logger.info("Skipping workout delivery \u{2014} no new workouts since last delivery")
                    return
                }
                try await webhookClient.post(sessions, to: "/workout")
                anchorStore.setLastDelivered(Date(), for: .workout)
                logger.info("Delivered \(sessions.count) workout(s)")
                deliveryLog.record(dataType: .workout, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Workout delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .workout, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
