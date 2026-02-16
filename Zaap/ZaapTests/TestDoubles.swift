import Foundation
import CoreLocation
import Combine
@testable import Zaap

// MARK: - Mock Webhook Client

final class MockWebhookClient: WebhookPosting, @unchecked Sendable {
    var postCallCount = 0
    var lastPath: String?
    var lastPayloadData: Data?
    var shouldThrow: Error?

    func post<T: Encodable>(_ payload: T, to path: String? = nil) async throws {
        postCallCount += 1
        lastPath = path
        lastPayloadData = try JSONEncoder().encode(payload)
        if let error = shouldThrow {
            throw error
        }
    }
}

// MARK: - Mock Location Publisher

final class MockLocationPublishing: LocationPublishing {
    let locationPublisher = PassthroughSubject<CLLocation, Never>()
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var isMonitoring = false
    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0

    func startMonitoring() {
        startMonitoringCallCount += 1
        isMonitoring = true
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        isMonitoring = false
    }
}

// MARK: - Mock Sleep Reader

final class MockSleepReader: SleepReading {
    var authorizationRequested = false
    var summaryToReturn: SleepDataReader.SleepSummary?
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchLastNightSummary() async throws -> SleepDataReader.SleepSummary {
        if let error = shouldThrow {
            throw error
        }
        return summaryToReturn!
    }
}

// MARK: - Mock Heart Rate Reader

final class MockHeartRateReader: HeartRateReading {
    var authorizationRequested = false
    var summaryToReturn: HeartRateReader.DailyHeartRateSummary?
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchDailySummary(for date: Date) async throws -> HeartRateReader.DailyHeartRateSummary {
        if let error = shouldThrow {
            throw error
        }
        return summaryToReturn!
    }
}

// MARK: - Mock Activity Reader

final class MockActivityReader: ActivityReading {
    var authorizationRequested = false
    var summaryToReturn: ActivityReader.ActivitySummary?
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchTodaySummary() async throws -> ActivityReader.ActivitySummary {
        if let error = shouldThrow {
            throw error
        }
        return summaryToReturn!
    }
}

// MARK: - Mock Workout Reader

final class MockWorkoutReader: WorkoutReading {
    var authorizationRequested = false
    var sessionsToReturn: [WorkoutReader.WorkoutSession] = []
    var shouldThrow: Error?

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = shouldThrow {
            throw error
        }
    }

    func fetchRecentSessions(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutReader.WorkoutSession] {
        if let error = shouldThrow {
            throw error
        }
        return sessionsToReturn
    }
}
