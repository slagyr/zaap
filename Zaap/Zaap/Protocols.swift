import Foundation
import CoreLocation
import Combine

/// Protocol for posting webhook payloads.
protocol WebhookPosting: Sendable {
    func post<T: Encodable>(_ payload: T, to path: String?) async throws
}

extension WebhookClient: WebhookPosting {}

/// Protocol for publishing location updates.
protocol LocationPublishing: AnyObject, Observable {
    var locationPublisher: PassthroughSubject<CLLocation, Never> { get }
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
    func fetchDailySummary() async throws -> HeartRateReader.DailyHeartRateSummary
}

extension HeartRateReader: HeartRateReading {}

/// Protocol for reading activity data.
protocol ActivityReading {
    func requestAuthorization() async throws
    func fetchTodaySummary() async throws -> ActivityReader.ActivitySummary
}

extension ActivityReader: ActivityReading {}
