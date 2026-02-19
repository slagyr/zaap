import Foundation
import CoreLocation
import Combine

/// Errors thrown by sendNow() on delivery services.
enum SendNowError: LocalizedError {
    case notConfigured
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Webhook URL and auth token must be configured."
        case .noData(let detail):
            return "No data available: \(detail)"
        }
    }
}

/// Protocol for posting webhook payloads.
protocol WebhookPosting: Sendable {
    func post<T: Encodable>(_ payload: T, to path: String?) async throws
    func postForeground<T: Encodable>(_ payload: T, to path: String?) async throws
}

extension WebhookClient: WebhookPosting {}

/// Protocol for publishing location updates.
@MainActor
protocol LocationPublishing: AnyObject {
    var locationPublisher: PassthroughSubject<CLLocation, Never> { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var isMonitoring: Bool { get }
    var currentLocation: CLLocation? { get }
    func startMonitoring()
    func stopMonitoring()
}

extension LocationManager: LocationPublishing {}

/// Protocol for reading sleep data.
protocol SleepReading {
    func requestAuthorization() async throws
    func fetchLastNightSummary() async throws -> SleepDataReader.SleepSummary
}

extension SleepDataReader: SleepReading {}

/// Protocol for reading heart rate data.
protocol HeartRateReading {
    func requestAuthorization() async throws
    func fetchDailySummary(for date: Date) async throws -> HeartRateReader.DailyHeartRateSummary
}

extension HeartRateReading {
    func fetchDailySummary() async throws -> HeartRateReader.DailyHeartRateSummary {
        try await fetchDailySummary(for: Date())
    }
}

extension HeartRateReader: HeartRateReading {}

/// Protocol for reading activity data.
protocol ActivityReading {
    func requestAuthorization() async throws
    func fetchTodaySummary() async throws -> ActivityReader.ActivitySummary
}

extension ActivityReader: ActivityReading {}

/// Protocol for reading workout data.
protocol WorkoutReading {
    func requestAuthorization() async throws
    func fetchRecentSessions(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutReader.WorkoutSession]
}

extension WorkoutReader: WorkoutReading {}
