import Foundation
import os

/// Fetches recent workouts and POSTs them via WebhookClient.
/// Mirrors SleepDeliveryService's pattern — query on demand and deliver via background session.
final class WorkoutDeliveryService {

    static let shared = WorkoutDeliveryService()

    private let logger = Logger(subsystem: "com.zaap.app", category: "WorkoutDelivery")

    private let workoutReader: WorkoutReader
    private let webhookClient: WebhookClient
    private let settings: SettingsManager

    init(
        workoutReader: WorkoutReader = .shared,
        webhookClient: WebhookClient = .shared,
        settings: SettingsManager = .shared
    ) {
        self.workoutReader = workoutReader
        self.webhookClient = webhookClient
        self.settings = settings
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

    /// Fetch the latest workouts and POST them to the webhook.
    func deliverLatest() {
        guard settings.isConfigured && settings.workoutTrackingEnabled else {
            logger.info("Skipping workout delivery — not configured or tracking disabled")
            return
        }

        Task {
            do {
                try await workoutReader.requestAuthorization()
                let sessions = try await workoutReader.fetchRecentSessions()
                try await webhookClient.post(sessions, to: "/workouts")
                logger.info("Delivered \(sessions.count) workout(s)")
            } catch {
                logger.error("Workout delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
