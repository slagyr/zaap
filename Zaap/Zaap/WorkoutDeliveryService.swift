import Foundation
import os

/// Fetches recent workouts and POSTs them via WebhookClient.
/// Mirrors SleepDeliveryService's pattern — query on demand and deliver via background session.
final class WorkoutDeliveryService {

    static let shared = WorkoutDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "WorkoutDelivery")

    private let workoutReader: any WorkoutReading
    private let webhookClient: any WebhookPosting
    private let settings: SettingsManager
    private let deliveryLog: any DeliveryLogging

    init(
        workoutReader: any WorkoutReading = WorkoutReader.shared,
        webhookClient: any WebhookPosting = WebhookClient.shared,
        settings: SettingsManager = .shared,
        deliveryLog: any DeliveryLogging = NullDeliveryLog()
    ) {
        self.workoutReader = workoutReader
        self.webhookClient = webhookClient
        self.settings = settings
        self.deliveryLog = deliveryLog
    }

    // MARK: - Public

    /// Start the service. If workout tracking was previously enabled, deliver the latest sessions.
    /// Call once at app launch.
    func start() {
        guard settings.workoutTrackingEnabled && settings.isConfigured else {
            logger.info("Workout delivery not started — disabled or not configured")
            return
        }
        deliverLatest()
    }

    /// Enable or disable workout tracking. Updates settings and triggers delivery if enabled.
    func setTracking(enabled: Bool) {
        settings.workoutTrackingEnabled = enabled
        if enabled {
            deliverLatest()
        }
    }


    /// Immediately fetch and POST workout data. Does not require tracking to be enabled.
    func sendNow() async throws {
        guard settings.isConfigured else { throw SendNowError.notConfigured }
        try await workoutReader.requestAuthorization()
        let sessions = try await workoutReader.fetchRecentSessions(from: nil, to: nil)
        try await webhookClient.postForeground(sessions, to: "/workout")
        logger.info("Send Now: Workout data delivered")
        deliveryLog.record(dataType: .workout, timestamp: Date(), success: true, errorMessage: nil)
    }
    /// Fetch the latest workouts and POST them to the webhook.
    func deliverLatest() {
        guard settings.isConfigured && settings.workoutTrackingEnabled else {
            logger.info("Skipping workout delivery — not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await workoutReader.requestAuthorization()
                let sessions = try await workoutReader.fetchRecentSessions(from: nil, to: nil)
                try await webhookClient.post(sessions, to: "/workout")
                logger.info("Delivered \(sessions.count) workout(s)")
                deliveryLog.record(dataType: .workout, timestamp: Date(), success: true, errorMessage: nil)
            } catch {
                logger.error("Workout delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryLog.record(dataType: .workout, timestamp: Date(), success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
