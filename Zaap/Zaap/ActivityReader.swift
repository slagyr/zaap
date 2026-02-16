import Foundation
import HealthKit
import os

/// Reads daily activity data (step count, walking+running distance, active energy burned)
/// from HealthKit using HKStatisticsQuery for daily summaries.
@Observable
final class ActivityReader {

    // MARK: - Types

    struct ActivitySummary: Codable, Sendable {
        let date: String            // YYYY-MM-DD
        let steps: Int
        let distanceMeters: Double  // walking + running distance
        let activeEnergyKcal: Double
        let timestamp: Date
    }

    enum ActivityError: Error, LocalizedError {
        case healthKitNotAvailable
        case authorizationDenied
        case noData

        var errorDescription: String? {
            switch self {
            case .healthKitNotAvailable: "HealthKit is not available on this device"
            case .authorizationDenied: "HealthKit activity data access denied"
            case .noData: "No activity data found for the requested period"
            }
        }
    }

    // MARK: - Properties

    static let shared = ActivityReader()

    private let healthStore: HKHealthStore?
    private let logger = Logger(subsystem: "com.zaap.app", category: "ActivityReader")

    private(set) var isAuthorized = false
    private(set) var lastError: String?

    // MARK: - Init

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        } else {
            self.healthStore = nil
        }
    }

    // MARK: - Authorization

    /// Request read access to step count, distance, and active energy.
    func requestAuthorization() async throws {
        guard let healthStore else {
            throw ActivityError.healthKitNotAvailable
        }

        let types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]

        try await healthStore.requestAuthorization(toShare: [], read: types)
        isAuthorized = true
        logger.info("HealthKit activity authorization granted")
    }

    // MARK: - Querying

    /// Fetch today's activity summary.
    func fetchTodaySummary() async throws -> ActivitySummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let steps = try await querySum(type: HKQuantityType(.stepCount), start: startOfDay, end: endOfDay, unit: .count())
        let distance = try await querySum(type: HKQuantityType(.distanceWalkingRunning), start: startOfDay, end: endOfDay, unit: .meter())
        let energy = try await querySum(type: HKQuantityType(.activeEnergyBurned), start: startOfDay, end: endOfDay, unit: .kilocalorie())

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let summary = ActivitySummary(
            date: dateFormatter.string(from: startOfDay),
            steps: Int(steps),
            distanceMeters: distance,
            activeEnergyKcal: energy,
            timestamp: Date()
        )

        logger.info("Activity summary: \(summary.steps) steps, \(String(format: "%.0f", distance))m, \(String(format: "%.0f", energy))kcal")
        return summary
    }

    // MARK: - Private

    private func querySum(type: HKQuantityType, start: Date, end: Date, unit: HKUnit) async throws -> Double {
        guard let healthStore else {
            throw ActivityError.healthKitNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}
